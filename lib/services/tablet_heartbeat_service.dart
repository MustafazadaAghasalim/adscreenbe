import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:android_id/android_id.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../config/server_config.dart';
import 'remote_config_service.dart';
import 'ota_update_service.dart';
import 'ad_service.dart';

class TabletHeartbeatService {
  static final TabletHeartbeatService _instance = TabletHeartbeatService._internal();
  factory TabletHeartbeatService() => _instance;
  TabletHeartbeatService._internal();

  static const _platform = MethodChannel('com.adscreen.kiosk/telemetry');

  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String? _tabletId;
  Timer? _timer;
  bool _isConnected = false;
  DateTime? _lastUpdate;
  DateTime _bootTime = DateTime.now();
  DateTime? _lastUnpluggedTime;
  
  bool _isLocked = false;
  String? _unlockPin;
  final _lockController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<DocumentSnapshot>? _tabletListener;

  String? get tabletId => _tabletId;
  bool get isConnected => _isConnected;
  DateTime? get lastUpdate => _lastUpdate;
  bool get isLocked => _isLocked;
  String? get unlockPin => _unlockPin;
  Stream<Map<String, dynamic>> get lockStatusStream => _lockController.stream;

  Future<void> initialize() async {
    print("TabletService: Initializing...");
    _bootTime = DateTime.now();
    await _initializeTabletId();
    await _requestPermissions();
    _initBatteryListener();
    
    // Register device immediately
    await registerDevice();
    
    // Start listening for commands
    _initFirestoreListener();
    
    // Start periodic heartbeat
    _timer = Timer.periodic(
      const Duration(seconds: ServerConfig.updateIntervalSeconds),
      (timer) => sendUpdate(),
    );
  }

  void _initFirestoreListener() {
    if (_tabletId == null) return;

    print("TabletService: Starting Firestore listener for $_tabletId");
    
    // 1. Listen to the Tablet Document (Commands, Lock Status)
    _tabletListener = _firestore
        .collection('active_tablets')
        .doc(_tabletId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        
        // Handle Lock Command
        if (data['locked'] != null) {
           updateLockState(data['locked'], data['unlock_pin']?.toString());
        }
        
        // Handle Remote Commands (like Reboot)
        if (data['command'] != null) {
           _handleCommand(data['command'], data['command_payload']);
        }
      }
    }, onError: (e) {
      print("TabletService: Tablet Doc listener error: $e");
    });

    // 2. Listen to Assigned Ads Sub-collection (Real-time Ad Triggers)
    _firestore
        .collection('active_tablets')
        .doc(_tabletId)
        .collection('assigned_ads')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final adData = change.doc.data();
          print("TabletService: New Ad Triggered from Firestore: ${adData?['name']}");
          // Trigger actual ad refresh in AdService
          AdService().refreshAdsFromFirestore();
        } else if (change.type == DocumentChangeType.removed) {
          print("TabletService: Ad Removed from Firestore: ${change.doc.id}");
          AdService().refreshAdsFromFirestore();
        }
      }
    }, onError: (e) {
       print("TabletService: Ad sub-collection listener error: $e");
    });
  }

  Future<void> _handleCommand(String command, dynamic payload) async {
    print("TabletService: Handling command: $command");
    
    // Acknowledge command by clearing it
    await _firestore.collection('active_tablets').doc(_tabletId).update({
      'command': FieldValue.delete(),
      'command_payload': FieldValue.delete(),
      'last_command_handled_at': FieldValue.serverTimestamp(),
    });

    switch (command) {
      case 'reboot':
        await _handleShutdown();
        break;
      case 'refresh_config':
        await RemoteConfigService.refreshConfig();
        break;
      case 'update_app':
        if (payload != null && payload['url'] != null) {
           OTAUpdateService.downloadAndInstallUpdate(payload['url'], 'remote');
        }
        break;
    }
  }

  Future<void> _handleShutdown() async {
    try {
      await _platform.invokeMethod('rebootDevice');
    } catch (e) {
      print("TabletService: Reboot failed: $e");
    }
  }

  // Register or Update Device in Firestore
  Future<void> registerDevice() async {
    await sendUpdate(); // Reuse sendUpdate logic for initial registration
  }

  void _initBatteryListener() {
    _battery.onBatteryStateChanged.listen((BatteryState state) {
      if (state == BatteryState.discharging) {
        _lastUnpluggedTime = DateTime.now();
        print("TabletService: Battery discharging. Last unplugged: $_lastUnpluggedTime");
      }
    });
  }

  Future<void> _initializeTabletId() async {
    final prefs = await SharedPreferences.getInstance();
    _tabletId = prefs.getString('tablet_id');

    if (_tabletId == null) {
      String? hardwareId;
      try {
        if (Platform.isAndroid) {
          const androidIdPlugin = AndroidId();
          hardwareId = await androidIdPlugin.getId();
        }
      } catch (e) {
        print("TabletService: Error getting ID: $e");
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(10000);
      
      if (hardwareId != null && hardwareId.isNotEmpty) {
        _tabletId = "tablet_$hardwareId";
      } else {
        _tabletId = "tablet_${timestamp}_$random";
      }

      await prefs.setString('tablet_id', _tabletId!);
      print("TabletService: Assigned ID: $_tabletId");
    } else {
      print("TabletService: Loaded ID: $_tabletId");
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.locationWhenInUse,
    ].request();
  }
  
  Future<String> _getIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return "Unknown";
  }

  Future<void> sendUpdate() async {
    if (_tabletId == null) return;

    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {}

      String deviceModel = "Unknown";
      String osVersion = "Unknown";
      
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceModel = "${androidInfo.brand} ${androidInfo.model}";
        osVersion = "Android ${androidInfo.version.release}";
      }

      var connectivityResult = await (Connectivity().checkConnectivity());
      String networkType = "None";
      if (connectivityResult == ConnectivityResult.mobile) networkType = "Cellular";
      else if (connectivityResult == ConnectivityResult.wifi) networkType = "WiFi";
      else if (connectivityResult == ConnectivityResult.ethernet) networkType = "Ethernet";

      double? freeSpaceMb;
      double? totalSpaceMb;
      try {
        freeSpaceMb = await DiskSpace.getFreeDiskSpaceForPath(
          Platform.isAndroid ? '/storage/emulated/0' : '/'
        );
        totalSpaceMb = await DiskSpace.getTotalDiskSpace;
      } catch (_) {}

      final ipAddress = await _getIpAddress();
      final adService = AdService();

      double temperature = 0.0;
      double brightness = 0.0;
      try {
         if (Platform.isAndroid) {
            temperature = await _platform.invokeMethod('getBatteryTemperature');
            brightness = await _platform.invokeMethod('getScreenBrightness');
         }
      } catch (_) {}

      final data = {
        "tablet_id": _tabletId,
        "status": "online", // Mark as online
        "last_seen": FieldValue.serverTimestamp(),
        "battery_percent": batteryLevel,
        "is_charging": batteryState == BatteryState.charging || batteryState == BatteryState.full,
        "charging_status": batteryState.toString().split('.').last,
        "last_unplugged": _lastUnpluggedTime?.toIso8601String(),
        "boot_time": _bootTime.toIso8601String(),
        "free_space_mb": freeSpaceMb?.toInt() ?? 0,
        "latitude": position?.latitude ?? 0.0,
        "longitude": position?.longitude ?? 0.0,
        "device_model": deviceModel,
        "os_version": osVersion,
        "network_type": networkType,
        "current_creative": adService.currentCreative,
        "ip_address": ipAddress,
        "storage_free": "${((freeSpaceMb ?? 0) / 1024).toStringAsFixed(1)} GB",
        "storage_total": "${((totalSpaceMb ?? 0) / 1024).toStringAsFixed(1)} GB",
        "temperature": "${temperature.toStringAsFixed(1)}°C",
        "brightness": brightness,
      };

      print("TabletService: Sending Firestore Update");
      
      // Use set with merge to create or update
      await _firestore.collection('active_tablets').doc(_tabletId).set(data, SetOptions(merge: true));
      
      _isConnected = true;
      _lastUpdate = DateTime.now();

    } catch (e) {
      print("TabletService: Error updating Firestore: $e");
      _isConnected = false;
    }
  }

  void updateLockState(bool locked, String? pin) {
    if (_isLocked != locked || _unlockPin != pin) {
      _isLocked = locked;
      _unlockPin = pin;
      _lockController.add({'locked': _isLocked, 'pin': _unlockPin});
      print("TabletService: Lock status updated: $_isLocked");
    }
  }

  void dispose() {
    _timer?.cancel();
    _tabletListener?.cancel();
    _lockController.close();
  }
}
