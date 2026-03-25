import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';

/// Heatmap Telemetry Service.
/// Tracks touch coordinates, dwell times, and interaction hotspots
/// on the kiosk screen. Data is buffered locally and batch-uploaded
/// for generating engagement heatmaps in the dashboard.
class HeatmapTelemetryService {
  static final HeatmapTelemetryService _instance = HeatmapTelemetryService._internal();
  factory HeatmapTelemetryService() => _instance;
  HeatmapTelemetryService._internal();

  final List<TouchEvent> _buffer = [];
  Timer? _uploadTimer;
  String? _currentAdId;
  String? _deviceId;

  /// Max buffer size before force-upload
  static const int maxBufferSize = 200;

  /// Upload interval
  static const Duration uploadInterval = Duration(minutes: 15);

  void start({required String deviceId}) {
    _deviceId = deviceId;
    _uploadTimer = Timer.periodic(uploadInterval, (_) => _batchUpload());
    print("HeatmapTelemetry: Started for device $deviceId");
  }

  /// Set the currently displayed ad.
  void setCurrentAd(String adId) {
    _currentAdId = adId;
  }

  /// Record a touch event with screen coordinates.
  void recordTouch({
    required double x,
    required double y,
    required double screenWidth,
    required double screenHeight,
    String type = 'tap',
  }) {
    _buffer.add(TouchEvent(
      x: x / screenWidth, // Normalize to 0-1
      y: y / screenHeight,
      adId: _currentAdId ?? 'unknown',
      type: type,
      timestamp: DateTime.now(),
    ));

    if (_buffer.length >= maxBufferSize) {
      _batchUpload();
    }
  }

  /// Record a dwell zone (area user stared at, using face detection).
  void recordDwellZone({
    required double centerX,
    required double centerY,
    required Duration duration,
  }) {
    _buffer.add(TouchEvent(
      x: centerX,
      y: centerY,
      adId: _currentAdId ?? 'unknown',
      type: 'dwell',
      dwellMs: duration.inMilliseconds,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _batchUpload() async {
    if (_buffer.isEmpty) return;

    final events = List<TouchEvent>.from(_buffer);
    _buffer.clear();

    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/api/heatmap_telemetry'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': _deviceId,
          'events': events.map((e) => e.toJson()).toList(),
          'uploadedAt': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        print("HeatmapTelemetry: Uploaded ${events.length} events.");
      } else {
        // Re-buffer on failure, but cap to prevent OOM
        if (_buffer.length + events.length <= maxBufferSize * 5) {
          _buffer.insertAll(0, events);
          print("HeatmapTelemetry: Upload failed (${response.statusCode}), re-buffered.");
        } else {
          print("HeatmapTelemetry: Upload failed (${response.statusCode}). Buffer full, dropping old events.");
        }
      }
    } catch (e) {
      // Re-buffer on error, but cap to prevent OOM
      if (_buffer.length + events.length <= maxBufferSize * 5) {
        _buffer.insertAll(0, events);
        print("HeatmapTelemetry: Upload error — $e. Re-buffered ${events.length} events.");
      } else {
        print("HeatmapTelemetry: Upload error — $e. Buffer full, dropping ${events.length} events to prevent OOM.");
      }
    }
  }

  /// Get current buffer stats.
  Map<String, dynamic> getStats() {
    return {
      'bufferedEvents': _buffer.length,
      'maxBuffer': maxBufferSize,
      'currentAd': _currentAdId,
      'deviceId': _deviceId,
    };
  }

  void stop() {
    _uploadTimer?.cancel();
    _batchUpload(); // Final flush
  }
}

class TouchEvent {
  final double x;
  final double y;
  final String adId;
  final String type;
  final int? dwellMs;
  final DateTime timestamp;

  TouchEvent({
    required this.x,
    required this.y,
    required this.adId,
    required this.type,
    this.dwellMs,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'adId': adId,
        'type': type,
        if (dwellMs != null) 'dwellMs': dwellMs,
        'ts': timestamp.toIso8601String(),
      };
}
