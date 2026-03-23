import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/server_config.dart';
import 'device_settings_service.dart';
import 'tablet_service.dart';
import 'ota_update_service.dart';

/// Low-latency WebSocket channel for instant admin commands.
/// Uses raw WebSocket (Node `/ws`) for:
///  - sub-100ms admin commands
///  - reliable reconnect with full device_settings resync on reconnect.
class AdminCommandService {
  static final AdminCommandService _instance = AdminCommandService._internal();
  factory AdminCommandService() => _instance;
  AdminCommandService._internal();

  static const MethodChannel _platform = MethodChannel('com.adscreen.kiosk/telemetry');

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isManuallyClosed = false;
  int _reconnectAttempts = 0;

  final _commandController = StreamController<AdminCommand>.broadcast();
  Stream<AdminCommand> get commandStream => _commandController.stream;

  /// Establish (or re-establish) the WebSocket connection.
  /// Automatically resyncs device settings on successful connect.
  void connect() {
    if (_isConnected) return;

    final tabletId = TabletService().tabletId ?? 'unknown';

    // Normalize REST base URL (http/https) to WebSocket URL (ws/wss)
    final wsBase = ServerConfig.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUrl = '$wsBase/ws?tablet_id=$tabletId';

    _isManuallyClosed = false;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Catch initial connection errors (e.g. SocketException, DNS lookup failed)
      // If we don't catch this, Dart will crash the whole app with an Unhandled Exception!
      _channel!.ready.catchError((error) {
        print('AdminWS: channel.ready error: $error');
        _handleDisconnect(reason: 'channel.ready error: $error');
      });

      _subscription = _channel!.stream.listen(
        (message) => _handleMessage(message),
        onDone: () {
          _handleDisconnect(reason: 'onDone');
        },
        onError: (error) {
          _handleDisconnect(reason: 'onError: $error');
        },
        cancelOnError: true,
      );

      _isConnected = true;
      _reconnectAttempts = 0;

      // Send registration as soon as we connect
      _send({
        'type': 'register',
        'tablet_id': tabletId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Immediately resync all device settings from server to avoid missed updates
      DeviceSettingsService().fetchFromServer();

      // Heartbeat every 15 seconds to keep connection alive
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _send({'type': 'ping', 'tablet_id': tabletId});
      });

      print('AdminWS: Connected to $wsUrl');
    } catch (e) {
      print('AdminWS: Connect exception: $e');
      _handleDisconnect(reason: 'connect_exception: $e');
    }
  }

  void _handleDisconnect({required String reason}) {
    if (_isManuallyClosed) return;

    print('AdminWS: Disconnected ($reason)');
    _isConnected = false;

    _subscription?.cancel();
    _subscription = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _scheduleReconnect();
  }

  void _handleMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      handleIncomingCommand(data);
    } catch (e) {
      print('AdminWS: Parse error: $e  raw=$raw');
    }
  }

  void handleIncomingCommand(Map<String, dynamic> data) {
    final type = (data['type'] ?? '') as String;
    print('AdminWS: Received command: $type');

    switch (type) {
      case 'volume_change':
      case 'set_volume':
        final volume = (data['volume'] as num?)?.toDouble() ??
            (data['value'] as num?)?.toDouble() ??
            0.5;
        VolumeController().setVolume(volume);
        _ack(data);
        break;

      case 'screen_wipe':
      case 'wipe_cache':
        _commandController.add(AdminCommand(type, data));
        _ack(data);
        break;

      case 'lock':
        final pin = data['pin']?.toString();
        TabletService().updateLockState(true, pin);
        _ack(data);
        break;

      case 'unlock':
        TabletService().updateLockState(false, null);
        _ack(data);
        break;

      case 'reboot':
      case 'shutdown':
        unawaited(_handleReboot(data));
        break;

      case 'screenshot':
        _commandController.add(AdminCommand('screenshot', data));
        _ack(data);
        break;

      case 'refresh_ads':
        _commandController.add(AdminCommand('refresh_ads', data));
        _ack(data);
        break;

      case 'brightness':
      case 'set_brightness':
        final brightness = (data['value'] as num?)?.toDouble() ?? 0.5;
        _commandController.add(AdminCommand('brightness', {'value': brightness}));
        _ack(data);
        break;

      case 'pong':
        // Heartbeat response — connection is alive
        break;

      case 'update_app':
        final tId = TabletService().tabletId ?? 'unknown';
        print('AdminWS: Triggering OTA update check for $tId');
        // This will check the backend and auto-download if an update exists
        OTAUpdateService.checkForUpdates(tId);
        _ack(data);
        break;

      case 'device_settings_updated':
        // Raw WS payload: { type, settings, timestamp } or flattened keys
        final rawSettings = data['settings'];
        final settings =
            (rawSettings is Map ? rawSettings.cast<String, dynamic>() : data);
        DeviceSettingsService().applySettings(settings);
        _ack(data);
        print('AdminWS: Device settings received & applied (${settings.length} keys)');
        break;

      default:
        // Handle wrapped admin commands: { type: 'admin_command', command: 'reboot', ... }
        if (type == 'admin_command' && data['command'] != null) {
          final innerCommand = data['command'] as String;
          print('AdminWS: Unwrapping admin_command → $innerCommand');
          final rewrapped = Map<String, dynamic>.from(data);
          rewrapped['type'] = innerCommand;
          handleIncomingCommand(rewrapped);
          return;
        }
        print('AdminWS: Unknown command type: $type');
        _commandController.add(AdminCommand(type, data));
    }
  }

  Future<void> _handleReboot(Map<String, dynamic> data) async {
    String? errorMessage;
    var success = false;

    try {
      final result = await _platform.invokeMethod('rebootDevice');
      success = result == true;
      if (!success) {
        errorMessage = 'rebootDevice returned non-true result: $result';
      }
    } catch (e) {
      errorMessage = e.toString();
      print('AdminWS: rebootDevice invoke failed: $errorMessage');
    }

    _send({
      'type': 'command_ack',
      'tablet_id': TabletService().tabletId,
      'command': 'reboot',
      'success': success,
      if (errorMessage != null) 'error': errorMessage,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (success) {
      _ack(data);
      return;
    }

    // Keep legacy stream dispatch for any UI-level fallback handling.
    _commandController.add(AdminCommand('reboot', data));
  }

  void _ack(Map<String, dynamic> original) {
    _send({
      'type': 'ack',
      'command_id': original['id'],
      'tablet_id': TabletService().tabletId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel == null || !_isConnected) {
      print('AdminWS: Drop send (not connected): $data');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      print('AdminWS: Send error: $e');
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    // Exponential backoff: 2s, 4s, 6s, ... capped at 60s
    final delaySeconds = (2 * _reconnectAttempts).clamp(2, 60);
    final delay = Duration(seconds: delaySeconds);
    print('AdminWS: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)...');

    _reconnectTimer = Timer(delay, () {
      if (_isManuallyClosed) return;
      connect();
    });
  }

  /// Send telemetry or status back to admin dashboard.
  void sendStatus(Map<String, dynamic> status) {
    _send({
      'type': 'status',
      'tablet_id': TabletService().tabletId,
      ...status,
    });
  }

  bool get isConnected => _isConnected;

  void disconnect() {
    _isManuallyClosed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }
}

class AdminCommand {
  final String type;
  final Map<String, dynamic> data;
  AdminCommand(this.type, this.data);
}
