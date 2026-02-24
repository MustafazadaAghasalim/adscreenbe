import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Network-Aware Bitrate Service.
/// Automatically determines optimal video quality (4K, 1080p, 720p, 360p)
/// based on the device's current network type and signal strength.
class NetworkAwareBitrateService {
  static final NetworkAwareBitrateService _instance = NetworkAwareBitrateService._internal();
  factory NetworkAwareBitrateService() => _instance;
  NetworkAwareBitrateService._internal();

  VideoQuality _currentQuality = VideoQuality.hd1080;
  StreamSubscription? _connectivitySub;
  final _qualityController = StreamController<VideoQuality>.broadcast();

  Stream<VideoQuality> get qualityStream => _qualityController.stream;
  VideoQuality get currentQuality => _currentQuality;

  void start() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      _evaluateQuality(result);
    });

    // Initial check
    Connectivity().checkConnectivity().then(_evaluateQuality);
    print("NetworkBitrate: Service started.");
  }

  void _evaluateQuality(ConnectivityResult result) {
    VideoQuality newQuality;

    if (result == ConnectivityResult.wifi) {
      // WiFi — assume good bandwidth
      newQuality = VideoQuality.hd1080;
    } else if (result == ConnectivityResult.mobile) {
      // Mobile — default to 720p, could be improved with actual speed test
      newQuality = VideoQuality.hd720;
    } else if (result == ConnectivityResult.ethernet) {
      // Ethernet — best quality
      newQuality = VideoQuality.uhd4k;
    } else if (result == ConnectivityResult.none) {
      // Offline — use lowest quality cached content
      newQuality = VideoQuality.sd360;
    } else {
      newQuality = VideoQuality.hd720;
    }

    if (newQuality != _currentQuality) {
      _currentQuality = newQuality;
      _qualityController.add(newQuality);
      print("NetworkBitrate: Quality switched to ${newQuality.label} (${newQuality.maxBitrate} kbps)");
    }
  }

  /// Get the best URL suffix for current quality.
  String getQualitySuffix() {
    switch (_currentQuality) {
      case VideoQuality.uhd4k:
        return '_4k';
      case VideoQuality.hd1080:
        return '_1080p';
      case VideoQuality.hd720:
        return '_720p';
      case VideoQuality.sd360:
        return '_360p';
    }
  }

  /// Get max file size recommendation for downloads (MB).
  int getMaxDownloadSizeMB() {
    switch (_currentQuality) {
      case VideoQuality.uhd4k:
        return 500;
      case VideoQuality.hd1080:
        return 200;
      case VideoQuality.hd720:
        return 100;
      case VideoQuality.sd360:
        return 30;
    }
  }

  void stop() {
    _connectivitySub?.cancel();
  }
}

enum VideoQuality {
  uhd4k(label: '4K UHD', maxBitrate: 25000, height: 2160),
  hd1080(label: '1080p FHD', maxBitrate: 8000, height: 1080),
  hd720(label: '720p HD', maxBitrate: 4000, height: 720),
  sd360(label: '360p SD', maxBitrate: 1000, height: 360);

  final String label;
  final int maxBitrate; // kbps
  final int height;

  const VideoQuality({
    required this.label,
    required this.maxBitrate,
    required this.height,
  });
}
