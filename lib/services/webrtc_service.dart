import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/server_config.dart';
import 'admin_command_service.dart';
import 'tablet_service.dart';

class WebRtcService {
  static final WebRtcService _instance = WebRtcService._internal();
  factory WebRtcService() => _instance;
  WebRtcService._internal();

  static const MethodChannel _captureChannel = MethodChannel('com.adscreen.kiosk/screen_capture');

  io.Socket? _signalSocket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localDisplayStream;
  StreamSubscription<AdminCommand>? _adminCommandSub;

  String? _sessionId;
  String? _adminClientId;
  bool _isInitialized = false;
  bool _isStreaming = false;

  String get _tabletId => TabletService().tabletId ?? 'unknown';

  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      }
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> initialize() async {
    if (_isInitialized) return;

    _adminCommandSub = AdminCommandService().commandStream.listen(_handleAdminCommand);
    _connectSignalingSocket();

    _isInitialized = true;
    debugPrint('WebRtcService initialized');
  }

  void _connectSignalingSocket() {
    if (_signalSocket != null) return;

    final socket = io.io(
      ServerConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'tablet_id': _tabletId, 'role': 'tablet'})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1500)
          .build(),
    );

    socket.onConnect((_) {
      debugPrint('WebRTC signaling connected');
      socket.emit('webrtc_register', {
        'role': 'tablet',
        'tablet_id': _tabletId,
      });
    });

    socket.on('request_stream', (payload) async {
      if (payload is Map) {
        await _startStreamSession(Map<String, dynamic>.from(payload));
      }
    });

    socket.on('webrtc_answer', (payload) async {
      if (payload is Map) {
        await _handleAnswer(Map<String, dynamic>.from(payload));
      }
    });

    socket.on('webrtc_ice_candidate', (payload) async {
      if (payload is Map) {
        await _handleRemoteIce(Map<String, dynamic>.from(payload));
      }
    });

    socket.on('stop_stream', (payload) async {
      await stopStreaming(reason: 'remote_stop');
    });

    socket.onDisconnect((_) {
      debugPrint('WebRTC signaling disconnected');
    });

    _signalSocket = socket;
  }

  Future<void> _startStreamSession(Map<String, dynamic> payload) async {
    final sessionId = payload['session_id']?.toString();
    final adminClientId = payload['admin_client_id']?.toString();

    if (sessionId == null || sessionId.isEmpty || adminClientId == null || adminClientId.isEmpty) {
      _emitSignal('webrtc_error', {
        'tablet_id': _tabletId,
        'message': 'Missing session_id/admin_client_id',
      });
      return;
    }

    if (_isStreaming) {
      await stopStreaming(reason: 'replace_session');
    }

    _sessionId = sessionId;
    _adminClientId = adminClientId;

    final hasConsent = await _ensureScreenCaptureConsent();
    if (!hasConsent) {
      _emitSignal('webrtc_error', {
        'tablet_id': _tabletId,
        'session_id': _sessionId,
        'admin_client_id': _adminClientId,
        'message': 'Screen capture permission denied',
      });
      return;
    }

    try {
      await _captureChannel.invokeMethod('startStream', {
        'uploadUrl': '${ServerConfig.baseUrl}/api/screenshot',
        'tabletId': _tabletId,
      });
    } catch (_) {
      // Keep going: flutter_webrtc capture can still work even if native helper fails.
    }

    try {
      await _createPeerConnection();
      await _createDisplayStream();

      final pc = _peerConnection;
      final stream = _localDisplayStream;
      if (pc == null || stream == null) {
        throw StateError('Peer connection or display stream unavailable');
      }

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      final offer = await pc.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await pc.setLocalDescription(offer);

      _emitSignal('webrtc_offer', {
        'tablet_id': _tabletId,
        'admin_client_id': _adminClientId,
        'session_id': _sessionId,
        'sdp': offer.sdp,
        'type': offer.type,
      });

      _isStreaming = true;
      debugPrint('WebRTC stream started: session=$_sessionId');
    } catch (e) {
      _emitSignal('webrtc_error', {
        'tablet_id': _tabletId,
        'admin_client_id': _adminClientId,
        'session_id': _sessionId,
        'message': 'Failed to start stream: $e',
      });
      await stopStreaming(reason: 'start_failed');
    }
  }

  Future<bool> _ensureScreenCaptureConsent() async {
    try {
      final hasConsent = await _captureChannel.invokeMethod<bool>('hasConsent') ?? false;
      if (hasConsent) return true;

      await _captureChannel.invokeMethod('requestConsent');

      // Give Android consent flow a short chance to complete if shown.
      await Future<void>.delayed(const Duration(seconds: 2));
      final consentAfterRequest = await _captureChannel.invokeMethod<bool>('hasConsent') ?? false;
      return consentAfterRequest;
    } catch (e) {
      debugPrint('Screen capture consent check failed: $e');
      return false;
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_rtcConfig);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (_sessionId == null || _adminClientId == null) return;
      _emitSignal('webrtc_ice_candidate', {
        'tablet_id': _tabletId,
        'admin_client_id': _adminClientId,
        'session_id': _sessionId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('WebRTC connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        stopStreaming(reason: 'connection_$state');
      }
    };
  }

  Future<void> _createDisplayStream() async {
    _localDisplayStream = await navigator.mediaDevices.getDisplayMedia({
      'video': {
        'frameRate': 10,
        'width': 720,
        'height': 1280,
      },
      'audio': false,
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    if (_peerConnection == null || _sessionId == null) return;
    if (payload['session_id']?.toString() != _sessionId) return;

    final sdp = payload['sdp']?.toString();
    final type = payload['type']?.toString() ?? 'answer';
    if (sdp == null || sdp.isEmpty) return;

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );
  }

  Future<void> _handleRemoteIce(Map<String, dynamic> payload) async {
    if (_peerConnection == null || _sessionId == null) return;
    if (payload['session_id']?.toString() != _sessionId) return;

    final candidate = payload['candidate']?.toString();
    final sdpMid = payload['sdpMid']?.toString();
    final sdpMLineIndex = payload['sdpMLineIndex'];

    if (candidate == null || candidate.isEmpty || sdpMLineIndex == null) return;

    final index = sdpMLineIndex is int ? sdpMLineIndex : int.tryParse('$sdpMLineIndex');
    if (index == null) return;

    await _peerConnection!.addCandidate(
      RTCIceCandidate(candidate, sdpMid, index),
    );
  }

  Future<void> stopStreaming({String reason = 'manual'}) async {
    if (!_isStreaming && _peerConnection == null && _localDisplayStream == null) {
      return;
    }

    try {
      await _captureChannel.invokeMethod('stopStream');
    } catch (_) {}

    try {
      _localDisplayStream?.getTracks().forEach((track) {
        track.stop();
      });
      await _localDisplayStream?.dispose();
    } catch (_) {}
    _localDisplayStream = null;

    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;

    _emitSignal('stop_stream', {
      'tablet_id': _tabletId,
      'admin_client_id': _adminClientId,
      'session_id': _sessionId,
      'reason': reason,
      'timestamp': DateTime.now().toIso8601String(),
    });

    _isStreaming = false;
    _sessionId = null;
    _adminClientId = null;
  }

  void _handleAdminCommand(AdminCommand command) {
    final type = command.type;
    if (type == 'request_stream') {
      _startStreamSession(command.data);
      return;
    }
    if (type == 'stop_stream') {
      stopStreaming(reason: 'command_bus_stop');
    }
  }

  void _emitSignal(String event, Map<String, dynamic> payload) {
    final socket = _signalSocket;
    if (socket == null || !socket.connected) {
      debugPrint('WebRTC signal drop ($event): ${jsonEncode(payload)}');
      return;
    }
    socket.emit(event, payload);
  }

  Future<void> dispose() async {
    await stopStreaming(reason: 'dispose');
    await _adminCommandSub?.cancel();
    _adminCommandSub = null;
    _signalSocket?.disconnect();
    _signalSocket = null;
    _isInitialized = false;
  }
}
