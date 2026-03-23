import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/server_config.dart';
import 'admin_command_service.dart';
import 'tablet_service.dart';

class MqttCommandService {
  static final MqttCommandService _instance = MqttCommandService._internal();
  factory MqttCommandService() => _instance;
  MqttCommandService._internal();

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  bool _manualClose = false;
  int _reconnectAttempts = 0;

  String get _tabletId => TabletService().tabletId ?? 'unknown';
  String get _commandsTopic => 'adscreen/tablets/$_tabletId/commands';
  String get _statusTopic => 'adscreen/tablets/$_tabletId/status';
  String get _ackTopic => 'adscreen/tablets/$_tabletId/acks';

  Future<void> connect() async {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    _manualClose = false;

    final client = MqttServerClient.withPort(
      ServerConfig.mqttHost,
      'tablet_$_tabletId',
      ServerConfig.mqttPort,
    );

    client.logging(on: false);
    client.secure = false;
    client.keepAlivePeriod = 30;
    client.autoReconnect = false;
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;

    final connMessage = MqttConnectMessage()
        .authenticateAs(ServerConfig.mqttUsername, ServerConfig.mqttPassword)
        .withWillTopic(_statusTopic)
        .withWillMessage(jsonEncode({'state': 'unexpected_disconnect', 'ts': DateTime.now().toIso8601String()}))
        .startClean();

    client.connectionMessage = connMessage;

    try {
      _client = client;
      await client.connect();
      final state = client.connectionStatus?.state;
      if (state != MqttConnectionState.connected) {
        throw StateError('MQTT not connected: $state');
      }

      _reconnectAttempts = 0;
      client.subscribe(_commandsTopic, MqttQos.atLeastOnce);
      _updatesSub?.cancel();
      _updatesSub = client.updates?.listen(_onMessages);

      _publishStatus('online');
      debugPrint('MQTT connected and subscribed: $_commandsTopic');
    } catch (e) {
      debugPrint('MQTT connect failed: $e');
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _manualClose = true;
    _publishStatus('offline');
    await _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
  }

  void _onConnected() {
    debugPrint('MQTT onConnected');
  }

  void _onDisconnected() {
    debugPrint('MQTT onDisconnected');
    if (_manualClose) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualClose) return;
    _reconnectAttempts++;
    final seconds = (_reconnectAttempts * 3).clamp(3, 60);
    Future<void>.delayed(Duration(seconds: seconds), () async {
      if (_manualClose) return;
      await connect();
    });
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final payload = event.payload;
      if (payload is! MqttPublishMessage) continue;

      final jsonText = MqttPublishPayload.bytesToStringAsString(payload.payload.message);
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is! Map<String, dynamic>) continue;

        final type = decoded['type']?.toString();
        final commandId = decoded['id']?.toString();

        if (type == null || type.isEmpty) {
          debugPrint('MQTT command missing type: $decoded');
          continue;
        }

        AdminCommandService().handleIncomingCommand(decoded);
        _publishAck(commandId, type, true);
      } catch (e) {
        debugPrint('MQTT command parse error: $e');
      }
    }
  }

  void _publishAck(String? commandId, String command, bool success) {
    final payload = {
      'tablet_id': _tabletId,
      'id': commandId,
      'command': command,
      'success': success,
      'ts': DateTime.now().toIso8601String(),
    };
    _publish(_ackTopic, payload);
  }

  void _publishStatus(String state) {
    _publish(_statusTopic, {
      'tablet_id': _tabletId,
      'state': state,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void _publish(String topic, Map<String, dynamic> payload) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }
}
