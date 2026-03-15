import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// ScreenCaptureService — Flutter-side bridge to the native ScreenCaptureService.
///
/// Manages MediaProjection consent, one-shot screenshots, and continuous
/// screen streaming for remote monitoring of the kiosk display.
///
/// USAGE:
///   final capture = ScreenCaptureService();
///   await capture.initialize();
///
///   // One-shot screenshot
///   await capture.takeScreenshot(tabletId: 'tablet_ABC123');
///
///   // Live stream (0.5 FPS for bandwidth)
///   await capture.startStream(tabletId: 'tablet_ABC123');
///   await capture.stopStream();
class ScreenCaptureService {
  static const _channel = MethodChannel('com.adscreen.kiosk/screen_capture');

  static final ScreenCaptureService _instance = ScreenCaptureService._();
  factory ScreenCaptureService() => _instance;
  ScreenCaptureService._();

  bool _hasConsent = false;
  bool get hasConsent => _hasConsent;

  String _uploadUrl = 'https://adscreen.az/api/screenshot';

  /// Initialize and check for existing consent.
  Future<void> initialize({String? uploadUrl}) async {
    if (uploadUrl != null) _uploadUrl = uploadUrl;
    try {
      _hasConsent = await _channel.invokeMethod<bool>('hasConsent') ?? false;
      debugPrint('[ScreenCapture] Consent cached: $_hasConsent');
    } catch (e) {
      debugPrint('[ScreenCapture] Init error: $e');
      _hasConsent = false;
    }
  }

  /// Request MediaProjection consent (shows system dialog once).
  /// On Device Owner tablets, this is typically auto-granted.
  Future<bool> requestConsent() async {
    try {
      await _channel.invokeMethod('requestConsent');
      // Consent result comes asynchronously via onActivityResult
      // Wait a moment and re-check
      await Future.delayed(const Duration(seconds: 3));
      _hasConsent = await _channel.invokeMethod<bool>('hasConsent') ?? false;
      return _hasConsent;
    } catch (e) {
      debugPrint('[ScreenCapture] Consent request error: $e');
      return false;
    }
  }

  /// Take a one-shot screenshot and upload to the server.
  Future<bool> takeScreenshot({required String tabletId}) async {
    try {
      if (!_hasConsent) {
        debugPrint('[ScreenCapture] No consent — requesting...');
        await requestConsent();
      }
      final result = await _channel.invokeMethod<bool>('takeScreenshot', {
        'uploadUrl': _uploadUrl,
        'tabletId': tabletId,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[ScreenCapture] Screenshot error: $e');
      return false;
    }
  }

  /// Start continuous screen streaming (0.5 FPS).
  Future<bool> startStream({required String tabletId}) async {
    try {
      if (!_hasConsent) {
        await requestConsent();
      }
      final result = await _channel.invokeMethod<bool>('startStream', {
        'uploadUrl': _uploadUrl,
        'tabletId': tabletId,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[ScreenCapture] Stream start error: $e');
      return false;
    }
  }

  /// Stop the screen stream.
  Future<bool> stopStream() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopStream');
      return result ?? false;
    } catch (e) {
      debugPrint('[ScreenCapture] Stream stop error: $e');
      return false;
    }
  }
}
