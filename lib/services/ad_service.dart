import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/server_config.dart';
import '../models/ad_model.dart';
import 'tablet_service.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  IO.Socket? _socket;
  final _adsController = StreamController<List<Ad>>.broadcast();
  Stream<List<Ad>> get adsStream => _adsController.stream;
  
  List<Ad> _cachedAds = [];
  List<Ad> get cachedAds => _cachedAds;

  // Debounce to prevent multiple rapid fetches
  Timer? _fetchDebounce;
  bool _isFetching = false;

  // Metrics tracking
  String _currentCreative = "None";
  int _impressionsToday = 0;
  String _loopStatus = "Syncing";

  String get currentCreative => _currentCreative;
  int get impressionsToday => _impressionsToday;
  String get loopStatus => _loopStatus;

  void setCurrentCreative(String name) {
    _currentCreative = name;
    _impressionsToday++;
  }

  void setLoopStatus(String status) {
    _loopStatus = status;
  }

  void initSocket() {
    if (_socket != null) {
      print("AdService: Socket already initialized.");
      return;
    }

    final tabletId = TabletService().tabletId ?? 'unknown';
    print("AdService: Initializing Socket.io connection to ${ServerConfig.baseUrl} as $tabletId");
    _socket = IO.io(ServerConfig.baseUrl, IO.OptionBuilder()
      .setTransports(['websocket'])
      .setQuery({'tablet_id': tabletId})
      .enableAutoConnect() 
      .enableReconnection()
      .setReconnectionAttempts(double.maxFinite.toInt())
      .setReconnectionDelay(2000)
      .build());

    _socket!.onConnect((_) {
      print('**** AdService: Socket Connected Successfully! ****');
      // Register this tablet with the server
      _socket!.emit('register_tablet', {
        'tablet_id': tabletId,
        'type': 'tablet',
        'connected_at': DateTime.now().toIso8601String(),
      });
      _debouncedFetch();
    });

    _socket!.onConnectError((err) => print('**** AdService: Socket Connect Error: $err ****'));
    _socket!.onConnectTimeout((_) => print('**** AdService: Socket Connect Timeout ****'));
    _socket!.onError((err) => print('**** AdService: Socket Error: $err ****'));
    _socket!.onReconnect((_) {
      print('**** AdService: Socket Reconnected! ****');
      _debouncedFetch();
    });

    // Listen for ad updates (server → tablet)
    _socket!.on('ad_update', (data) {
      print('AdService: Received ad_update event: $data');
      if (data is Map && data['tablet_id'] != null) {
        final targetId = data['tablet_id'];
        final myId = TabletService().tabletId;
        if (targetId == myId) {
          print("AdService: Update is for me ($myId). Fetching...");
          _debouncedFetch();
        } else {
          print("AdService: Update is for $targetId, ignoring.");
        }
      } else {
        // Broadcast or unknown format - fetch to be safe
        print("AdService: Broadcast update. Fetching...");
        _debouncedFetch();
      }
    });

    // Listen for lock commands via Socket.IO (server → tablet)
    _socket!.on('tablet_lock_command', (data) {
      print('AdService: Received lock command: $data');
      if (data is Map) {
        final targetId = data['tablet_id'];
        final myId = TabletService().tabletId;
        if (targetId == myId) {
          final locked = data['locked'] == true;
          final pin = data['pin']?.toString();
          TabletService().updateLockState(locked, pin);
          print("AdService: Lock command applied: locked=$locked");
        }
      }
    });

    // Listen for remote commands via Socket.IO (server → tablet)
    _socket!.on('remote_command', (data) {
      print('AdService: Received remote command: $data');
      if (data is Map) {
        final targetId = data['tablet_id'];
        final myId = TabletService().tabletId;
        if (targetId == myId) {
          final command = data['command']?.toString();
          if (command != null) {
            print("AdService: Executing remote command: $command");
            // Handle via TabletHeartbeatService
          }
        }
      }
    });

    _socket!.onDisconnect((_) => print('AdService: Socket Disconnected'));
    
    // Initial fetch on startup
    _debouncedFetch();
  }

  /// Debounced fetch to prevent rapid-fire requests
  void _debouncedFetch() {
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchAndDownloadAds();
    });
  }

  /// Called by TelemetryService to push real-time telemetry via Socket.IO
  void emitTelemetry(Map<String, dynamic> payload) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('tablet_telemetry', payload);
    }
  }

  /// Called by TabletHeartbeatService when Firestore ad sub-collection changes
  void refreshAdsFromFirestore() {
    print("AdService: Firestore ad change detected, refreshing...");
    _debouncedFetch();
  }

  Future<void> _fetchAndDownloadAds() async {
    if (_isFetching) {
      print("AdService: Already fetching, skipping duplicate request.");
      return;
    }
    _isFetching = true;

    final tabletId = TabletService().tabletId;
    if (tabletId == null) {
      print("**** AdService: No Tablet ID yet, skipping fetch. ****");
      _isFetching = false;
      return;
    }

    try {
      print("**** AdService: Fetching ad list for $tabletId... ****");
      final uri = Uri.parse("${ServerConfig.adRetrievalEndpoint}?tablet_id=$tabletId");
      final response = await http.get(uri);
      
      print("**** AdService: HTTP ${response.statusCode} ****");
      print("**** AdService: Raw Body: ${response.body} ****"); 

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> adsJson = data['ads'] ?? [];
        
        List<Ad> fetchedAds = adsJson.map((json) {
          if (json['imageUrl'] == null && json['url'] != null) {
            json['imageUrl'] = json['url'];
          }
           return Ad.fromJson(json);
        }).toList();

        print("**** AdService: Fetched ${fetchedAds.length} ads. Starting synchronization... ****");

        // Smart Download
        try {
          _cachedAds = await _synchronizeFiles(fetchedAds);
          setLoopStatus("Synced");
          print("**** AdService: Sync Success. Cached Ads: ${_cachedAds.length} ****");
        } catch (syncError) {
          setLoopStatus("Sync Error");
          print("**** AdService: SYNC ERROR: $syncError ****");
        }
        
        // Notify UI
        _adsController.add(_cachedAds);
        
      } else {
        print("**** AdService: Failed to fetch ads: ${response.statusCode} ****");
      }
    } catch (e, stackTrace) {
      print("**** AdService: Fetch error: $e ****");
      print("**** StackTrace: $stackTrace ****");
    } finally {
      _isFetching = false;
    }
  }

  Future<List<Ad>> _synchronizeFiles(List<Ad> newAds) async {
    final appDir = await getApplicationDocumentsDirectory();
    final adDir = Directory("${appDir.path}/ads");
    
    // Ensure ads directory exists
    if (!await adDir.exists()) {
      await adDir.create(recursive: true);
    }

    List<Ad> readyAds = [];
    Set<String> activeFilePaths = {};
    
    // 1. Download new/missing files
    for (var ad in newAds) {
      try {
        final url = ad.imageUrl;
        if (url.isEmpty) continue;

        // Create filename from ID and original name to ensure uniqueness
        final cleanName = url.split('/').last.split('?').first;
        final fileName = "${ad.id}_$cleanName";
        final filePath = "${adDir.path}/$fileName";
        final file = File(filePath);
        
        activeFilePaths.add(filePath);

        bool exists = await file.exists();
        if (exists) {
           final length = await file.length();
           if (length < 1024) { // Less than 1KB is suspicious for media
             print("AdService: File ${ad.id} is too small ($length bytes). Deleting and re-downloading.");
             await file.delete();
             exists = false;
           }
        }

        if (!exists) {
           print("AdService: Downloading new file for ${ad.id}...");
           final response = await http.get(Uri.parse(url));
           if (response.statusCode == 200) {
             await file.writeAsBytes(response.bodyBytes);
             // Verify again
             final length = await file.length();
             if (length < 1024) {
                print("AdService: Downloaded file is too small ($length). Possible server error/HTML response.");
                // Try to read it to see if it's text (debug)
                try {
                  print("AdService: Content: ${utf8.decode(response.bodyBytes.sublist(0, min(100, response.bodyBytes.length)))}");
                } catch (_) {}
                continue; // Skip valid add logic
             }
             print("AdService: Downloaded.");
           } else {
             print("AdService: Download failed ${response.statusCode}");
             continue; // Skip this ad if download fails
           }
        }
        
        ad.localPath = filePath;
        readyAds.add(ad);
      } catch (e) {
        print("AdService: Error syncing file for ${ad.id}: $e");
      }
    }
    
    // 2. Cleanup old files
    try {
      if (await adDir.exists()) {
        final List<FileSystemEntity> files = adDir.listSync();
        for (var file in files) {
          if (file is File && !activeFilePaths.contains(file.path)) {
             print("AdService: Deleting old file: ${file.path.split('/').last}");
             try {
               await file.delete();
             } catch (e) { print("Error deleting: $e"); }
          }
        }
      }
    } catch (e) {
      print("AdService: Cleanup error: $e");
    }
    
    return readyAds;
  }
}
