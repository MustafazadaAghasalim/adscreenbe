import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/server_config.dart';
import 'tablet_service.dart';

/// Local SQLite buffer for Proof-of-Play logs.
/// Saves all impression/play logs locally when offline, then batch-uploads
/// them when Wi-Fi returns — saving battery by avoiding constant retries.
class ProofOfPlayService {
  static final ProofOfPlayService _instance = ProofOfPlayService._internal();
  factory ProofOfPlayService() => _instance;
  ProofOfPlayService._internal();

  Database? _db;
  Timer? _uploadTimer;
  bool _isUploading = false;

  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'proof_of_play.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE play_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ad_id TEXT NOT NULL,
            ad_name TEXT,
            tablet_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            duration_seconds INTEGER,
            completed INTEGER DEFAULT 0,
            attention_score REAL DEFAULT 0.0,
            latitude REAL,
            longitude REAL,
            synced INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.execute('''
          CREATE TABLE touch_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            log_id INTEGER,
            x REAL,
            y REAL,
            timestamp TEXT,
            synced INTEGER DEFAULT 0,
            FOREIGN KEY (log_id) REFERENCES play_logs(id)
          )
        ''');
        await db.execute('CREATE INDEX idx_synced ON play_logs(synced)');
        await db.execute('CREATE INDEX idx_touch_synced ON touch_events(synced)');
      },
    );

    // Start periodic upload check every 5 minutes (saves battery vs 60s)
    _uploadTimer = Timer.periodic(const Duration(seconds: 300), (_) => _tryBatchUpload());
    print("ProofOfPlay: SQLite buffer initialized.");
  }

  /// Log a single ad play event locally.
  Future<int> logPlay({
    required String adId,
    required String adName,
    required String tabletId,
    required DateTime startedAt,
    DateTime? endedAt,
    int durationSeconds = 0,
    bool completed = false,
    double attentionScore = 0.0,
    double? latitude,
    double? longitude,
  }) async {
    if (_db == null) return -1;
    final id = await _db!.insert('play_logs', {
      'ad_id': adId,
      'ad_name': adName,
      'tablet_id': tabletId,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'completed': completed ? 1 : 0,
      'attention_score': attentionScore,
      'latitude': latitude,
      'longitude': longitude,
      'synced': 0,
    });
    print("ProofOfPlay: Logged play #$id for $adName");
    return id;
  }

  /// Log a touch/heatmap event.
  Future<void> logTouch(int logId, double x, double y) async {
    if (_db == null) return;
    await _db!.insert('touch_events', {
      'log_id': logId,
      'x': x,
      'y': y,
      'timestamp': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  /// Get count of unsynced logs.
  Future<int> unsyncedCount() async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM play_logs WHERE synced = 0');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Attempt batch upload when network is available.
  Future<void> _tryBatchUpload() async {
    if (_isUploading || _db == null) return;

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    _isUploading = true;
    try {
      // Get unsynced play logs (batch of 50)
      final logs = await _db!.query('play_logs', where: 'synced = 0', limit: 50);
      if (logs.isEmpty) {
        _isUploading = false;
        return;
      }

      // Get associated touch events (parameterized query to prevent SQL injection)
      final logIds = logs.map((l) => l['id']).toList();
      final placeholders = logIds.map((_) => '?').join(',');
      final touches = await _db!.query('touch_events',
        where: 'log_id IN ($placeholders) AND synced = 0',
        whereArgs: logIds,
      );

      // Build payload
      final payload = {
        'tablet_id': TabletService().tabletId ?? 'unknown',
        'play_logs': logs.map((l) => {
          ...l,
          'touches': touches.where((t) => t['log_id'] == l['id']).toList(),
        }).toList(),
        'batch_size': logs.length,
        'uploaded_at': DateTime.now().toIso8601String(),
      };

      // Upload
      final response = await http.post(
        Uri.parse("${ServerConfig.baseUrl}/api/proof_of_play_batch"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Mark as synced (parameterized)
        await _db!.rawUpdate(
          'UPDATE play_logs SET synced = 1 WHERE id IN ($placeholders)', logIds,
        );
        await _db!.rawUpdate(
          'UPDATE touch_events SET synced = 1 WHERE log_id IN ($placeholders)', logIds,
        );
        print("ProofOfPlay: Batch uploaded ${logs.length} logs successfully.");
      } else {
        print("ProofOfPlay: Upload failed (${response.statusCode}). Will retry.");
      }
    } catch (e) {
      print("ProofOfPlay: Batch upload error: $e. Will retry next cycle.");
    } finally {
      _isUploading = false;
    }
  }

  /// Force an immediate upload attempt.
  Future<void> forceUpload() => _tryBatchUpload();

  /// Cleanup old synced records (keep last 7 days)
  Future<void> cleanup() async {
    if (_db == null) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    final deleted = await _db!.delete('play_logs',
      where: 'synced = 1 AND created_at < ?', whereArgs: [cutoff]);
    if (deleted > 0) print("ProofOfPlay: Cleaned up $deleted old records.");
  }

  void dispose() {
    _uploadTimer?.cancel();
    _db?.close();
  }
}
