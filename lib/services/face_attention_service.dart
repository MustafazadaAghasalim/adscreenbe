import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';

/// Face Attention Detection Service.
/// Uses the device front camera to detect if someone is looking
/// at the screen. Logs attention metrics for ad engagement analytics.
/// NOTE: google_mlkit_face_detection handles the actual ML processing.
/// This service wraps the detection logic for kiosk use.
class FaceAttentionService {
  static final FaceAttentionService _instance = FaceAttentionService._internal();
  factory FaceAttentionService() => _instance;
  FaceAttentionService._internal();

  bool _isActive = false;
  Timer? _reportTimer;
  String? _deviceId;

  // Attention metrics buffer
  final List<AttentionEvent> _events = [];
  int _totalDetections = 0;
  int _facesDetectedCount = 0;

  void start({required String deviceId}) {
    _deviceId = deviceId;
    _isActive = true;

    // Report metrics every 30 minutes
    _reportTimer = Timer.periodic(const Duration(minutes: 30), (_) => _uploadMetrics());

    print("FaceAttention: Service started for device $deviceId");
    print("FaceAttention: NOTE — Camera integration requires platform setup.");
  }

  /// Record an attention detection result.
  /// Called by the camera preview handler when a frame is analyzed.
  void recordDetection({
    required int facesFound,
    required String currentAdId,
    double? avgAttentionScore, // 0.0-1.0 based on face angle
  }) {
    _totalDetections++;
    if (facesFound > 0) {
      _facesDetectedCount++;
    }

    _events.add(AttentionEvent(
      facesFound: facesFound,
      adId: currentAdId,
      attentionScore: avgAttentionScore ?? (facesFound > 0 ? 0.7 : 0.0),
      timestamp: DateTime.now(),
    ));

    // Keep buffer manageable
    if (_events.length > 500) {
      _uploadMetrics();
    }
  }

  /// Get current attention rate (faces detected / total scans).
  double get attentionRate {
    if (_totalDetections == 0) return 0;
    return _facesDetectedCount / _totalDetections;
  }

  Future<void> _uploadMetrics() async {
    if (_events.isEmpty) return;

    final batch = List<AttentionEvent>.from(_events);
    _events.clear();

    try {
      await http.post(
        Uri.parse('${ServerConfig.baseUrl}/api/attention_metrics'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': _deviceId,
          'events': batch.map((e) => e.toJson()).toList(),
          'summary': {
            'totalScans': _totalDetections,
            'facesDetected': _facesDetectedCount,
            'attentionRate': attentionRate,
          },
          'uploadedAt': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 15));

      print("FaceAttention: Uploaded ${batch.length} events.");
    } catch (e) {
      // Re-buffer
      _events.insertAll(0, batch);
      print("FaceAttention: Upload failed — $e");
    }
  }

  Map<String, dynamic> getStats() {
    return {
      'isActive': _isActive,
      'totalScans': _totalDetections,
      'facesDetected': _facesDetectedCount,
      'attentionRate': '${(attentionRate * 100).toStringAsFixed(1)}%',
      'bufferedEvents': _events.length,
    };
  }

  void stop() {
    _isActive = false;
    _reportTimer?.cancel();
    _uploadMetrics(); // Final flush
  }
}

class AttentionEvent {
  final int facesFound;
  final String adId;
  final double attentionScore;
  final DateTime timestamp;

  AttentionEvent({
    required this.facesFound,
    required this.adId,
    required this.attentionScore,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'faces': facesFound,
        'adId': adId,
        'score': attentionScore,
        'ts': timestamp.toIso8601String(),
      };
}

/// Widget to display attention indicator (optional debug overlay).
class AttentionIndicator extends StatelessWidget {
  final double attentionRate;

  const AttentionIndicator({super.key, required this.attentionRate});

  @override
  Widget build(BuildContext context) {
    final color = attentionRate > 0.5
        ? const Color(0xFF3FB950)
        : attentionRate > 0.2
            ? const Color(0xFFD29922)
            : const Color(0xFFF85149);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            '${(attentionRate * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
