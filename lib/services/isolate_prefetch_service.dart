import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import '../models/ad_model.dart';

/// Isolate-based video/image pre-fetcher.
/// Downloads upcoming ads in a background isolate so the main UI thread
/// never stutters during ad transitions.
class IsolatePrefetchService {
  static final IsolatePrefetchService _instance = IsolatePrefetchService._internal();
  factory IsolatePrefetchService() => _instance;
  IsolatePrefetchService._internal();

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _isRunning = false;

  final _progressController = StreamController<PrefetchProgress>.broadcast();
  Stream<PrefetchProgress> get progressStream => _progressController.stream;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
    );

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is Map<String, dynamic>) {
        _progressController.add(PrefetchProgress.fromMap(message));
      }
    });

    print("IsolatePrefetch: Background prefetch isolate started.");
  }

  /// Queue a list of ads for background download.
  /// [currentIndex] tells the isolate which ad is playing so it prefetches the NEXT ones.
  Future<void> prefetchUpcoming(List<Ad> ads, int currentIndex, String cacheDir) async {
    if (_sendPort == null || ads.isEmpty) return;

    // Build the list of URLs to prefetch (next 3 ads)
    final upcoming = <Map<String, String>>[];
    for (int i = 1; i <= 3; i++) {
      final idx = (currentIndex + i) % ads.length;
      if (ads[idx].imageUrl.isNotEmpty) {
        upcoming.add({
          'id': ads[idx].id,
          'url': ads[idx].imageUrl,
          'type': ads[idx].type,
        });
      }
    }

    _sendPort!.send({
      'action': 'prefetch',
      'items': upcoming,
      'cacheDir': cacheDir,
    });
  }

  /// Check if a file is already cached.
  static Future<bool> isCached(String adId, String url, String cacheDir) async {
    final cleanName = url.split('/').last.split('?').first;
    final filePath = "$cacheDir/${adId}_$cleanName";
    return File(filePath).exists();
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
    _sendPort = null;
    _isRunning = false;
  }

  /// The actual isolate entry point — runs in a separate thread.
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) async {
      if (message is Map<String, dynamic> && message['action'] == 'prefetch') {
        final items = (message['items'] as List).cast<Map<String, String>>();
        final cacheDir = message['cacheDir'] as String;

        for (final item in items) {
          try {
            final id = item['id']!;
            final url = item['url']!;
            final cleanName = url.split('/').last.split('?').first;
            final filePath = "$cacheDir/${id}_$cleanName";
            final file = File(filePath);

            if (await file.exists() && await file.length() > 1024) {
              mainSendPort.send({
                'status': 'cached',
                'id': id,
                'path': filePath,
              });
              continue;
            }

            // Download in isolate — zero impact on UI thread
            final response = await http.get(Uri.parse(url));
            if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
              await Directory(cacheDir).create(recursive: true);
              await file.writeAsBytes(response.bodyBytes);
              mainSendPort.send({
                'status': 'downloaded',
                'id': id,
                'path': filePath,
                'bytes': response.bodyBytes.length,
              });
            } else {
              mainSendPort.send({
                'status': 'failed',
                'id': id,
                'reason': 'HTTP ${response.statusCode} or too small',
              });
            }
          } catch (e) {
            mainSendPort.send({
              'status': 'error',
              'id': item['id'] ?? 'unknown',
              'reason': e.toString(),
            });
          }
        }
      }
    });
  }
}

class PrefetchProgress {
  final String status;
  final String id;
  final String? path;
  final int? bytes;
  final String? reason;

  PrefetchProgress({
    required this.status,
    required this.id,
    this.path,
    this.bytes,
    this.reason,
  });

  factory PrefetchProgress.fromMap(Map<String, dynamic> map) {
    return PrefetchProgress(
      status: map['status'] ?? 'unknown',
      id: map['id'] ?? '',
      path: map['path'],
      bytes: map['bytes'],
      reason: map['reason'],
    );
  }
}
