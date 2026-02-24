import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Adaptive Image Cache Manager.
/// Provides intelligent caching with configurable max size,
/// stale duration, and LRU eviction for kiosk ad images.
class AdaptiveCacheManager {
  static final AdaptiveCacheManager _instance = AdaptiveCacheManager._internal();
  factory AdaptiveCacheManager() => _instance;
  AdaptiveCacheManager._internal();

  late CacheManager _cacheManager;
  bool _initialized = false;

  /// Max cache size in bytes (default 500 MB for kiosk)
  static const int maxCacheBytes = 500 * 1024 * 1024;

  /// Cache stale period (7 days)
  static const Duration stalePeriod = Duration(days: 7);

  /// Max concurrent downloads
  static const int maxConcurrent = 4;

  Future<void> initialize() async {
    if (_initialized) return;

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/ad_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    _cacheManager = CacheManager(
      Config(
        'adscreen_cache',
        stalePeriod: stalePeriod,
        maxNrOfCacheObjects: 200,
        repo: JsonCacheInfoRepository(databaseName: 'adscreen_cache_db'),
        fileService: HttpFileService(),
      ),
    );

    _initialized = true;
    print("AdaptiveCache: Initialized with ${maxCacheBytes ~/ (1024 * 1024)} MB limit.");

    // Run initial cleanup
    await _enforceSizeLimit();
  }

  CacheManager get manager {
    if (!_initialized) {
      throw StateError('AdaptiveCacheManager not initialized. Call initialize() first.');
    }
    return _cacheManager;
  }

  /// Download and cache a file, returns the local path.
  Future<String?> getCachedFile(String url) async {
    try {
      final fileInfo = await _cacheManager.downloadFile(url);
      return fileInfo.file.path;
    } catch (e) {
      print("AdaptiveCache: Failed to cache $url — $e");
      // Try to get from cache even if download fails
      try {
        final cached = await _cacheManager.getFileFromCache(url);
        if (cached != null) {
          return cached.file.path;
        }
      } catch (_) {}
      return null;
    }
  }

  /// Preload a list of URLs.
  Future<void> preloadUrls(List<String> urls) async {
    final futures = <Future>[];
    for (int i = 0; i < urls.length; i++) {
      futures.add(_cacheManager.downloadFile(urls[i]).catchError((e) {
        print("AdaptiveCache: Preload failed for ${urls[i]}");
        return e; // return to satisfy non-void catchError
      }));

      // Throttle concurrent downloads
      if (futures.length >= maxConcurrent) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    print("AdaptiveCache: Preloaded ${urls.length} files.");
  }

  /// Enforce maximum cache directory size with LRU eviction.
  Future<void> _enforceSizeLimit() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/ad_cache');
      if (!await cacheDir.exists()) return;

      final files = await cacheDir.list(recursive: true).where((e) => e is File).cast<File>().toList();

      int totalSize = 0;

      for (final file in files) {
        final stat = await file.stat();
        totalSize += stat.size;
      }

      if (totalSize <= maxCacheBytes) return;

      // Sort by last accessed (oldest first) — use async stat already fetched
      final fileTimes = <File, DateTime>{};
      for (final file in files) {
        try {
          final stat = await file.stat();
          fileTimes[file] = stat.accessed;
        } catch (_) {
          fileTimes[file] = DateTime(2000); // Treat errors as old
        }
      }
      files.sort((a, b) {
        return (fileTimes[a] ?? DateTime(2000)).compareTo(fileTimes[b] ?? DateTime(2000));
      });

      // Delete oldest files until under limit
      int bytesFreed = 0;
      for (final file in files) {
        if (totalSize - bytesFreed <= maxCacheBytes) break;
        final size = await file.length();
        await file.delete();
        bytesFreed += size;
      }

      print("AdaptiveCache: Freed ${bytesFreed ~/ 1024} KB from cache.");
    } catch (e) {
      print("AdaptiveCache: Cache cleanup error: $e");
    }
  }

  /// Get current cache stats.
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/ad_cache');
      if (!await cacheDir.exists()) {
        return {'files': 0, 'sizeMB': 0};
      }

      int count = 0;
      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          count++;
          totalSize += await entity.length();
        }
      }

      return {
        'files': count,
        'sizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(1),
        'limitMB': maxCacheBytes ~/ (1024 * 1024),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Clear all cached data.
  Future<void> clearAll() async {
    await _cacheManager.emptyCache();
    print("AdaptiveCache: All cache cleared.");
  }
}
