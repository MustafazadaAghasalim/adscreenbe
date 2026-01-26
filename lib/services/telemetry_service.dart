import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'ad_service.dart';
import 'tablet_service.dart';

class TelemetryService {
  final Dio _dio = Dio();
  final _battery = Battery();
  final _androidIdPlugin = const AndroidId();
  Timer? _timer;

  // BASE_URL login is simpler here: hardcode check or use environment.
  // Debug vs Release logic can be handled by kReleaseMode
  String get baseUrl => kReleaseMode ? "https://adscreen.az/" : "http://10.10.3.61:3000/";

  void start() {
    // Check permissions first? Assuming logic handles it in UI or here.
    _timer = Timer.periodic(const Duration(seconds: 60), (timer) => _sendTelemetry());
    _sendTelemetry(); // Send immediately
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

  Future<void> _sendTelemetry() async {
    try {
      final String? deviceId = await _androidIdPlugin.getId();
      final int batteryLevel = await _battery.batteryLevel;
      
      // Get Location & Speed
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      // Get IP
      String ip = await _getIpAddress();
      
      // Get Storage
      double? freeSpace = await DiskSpace.getFreeDiskSpace;
      double? totalSpace = await DiskSpace.getTotalDiskSpace;
      
      // Get Connectivity
      var connectivityResult = await (Connectivity().checkConnectivity());
      String networkType = connectivityResult.toString().split('.').last;

      final payload = {
        "tablet_id": TabletService().tabletId ?? "REAL_DEVICE_${deviceId?.substring(0, 5) ?? 'UNKNOWN'}",
        "battery_percent": batteryLevel,
        "latitude": position.latitude,
        "longitude": position.longitude,
        "speed": position.speed,
        "ip_address": ip,
        "storage_free": ((freeSpace ?? 0) / 1024).toStringAsFixed(1), // GB
        "storage_total": ((totalSpace ?? 0) / 1024).toStringAsFixed(1), // GB
        "network_type": networkType,
        "current_creative": AdService().currentCreative,
        "impressions_today": AdService().impressionsToday,
        "loop_status": AdService().loopStatus,
        "temperature": "38°C", // Mocked
        "brightness": 0.8, // Mocked
        "signal_strength": "Excellent", // Mocked
        "data_usage": "1.2 GB", // Mocked
        "driver_id": "DRV-9921", // Mocked
      };

      await _dio.post(
        "$baseUrl/api/update_tablet_status",
        data: payload,
      );
      
      if (kDebugMode) {
        print("Telemetry Sent: $payload to $baseUrl");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Telemetry Error: $e");
      }
    }
  }

  void stop() {
    _timer?.cancel();
  }
}
