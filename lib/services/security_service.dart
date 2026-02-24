import 'dart:io';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'tablet_service.dart';
import '../config/server_config.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  bool _isCapturing = false;

  Future<void> reportIntruder() async {
    if (_isCapturing) return;
    _isCapturing = true;
    print("SecurityService: Intruder detected! Starting 3s video capture...");

    try {
      // 1. Get Location first to ensure we have it for the report
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );
      } catch (e) {
        print("SecurityService: Could not get location: $e");
      }

      // 2. Capture Video Silently (3 seconds)
      final videoFile = await _recordVideoSilently(durationSeconds: 3);
      if (videoFile == null) {
        print("SecurityService: FAILED to record video. Aborting.");
        return;
      }

      // 3. Upload to Azure Blob Storage (via our Node.js backend)
      print("SecurityService: Uploading video and alert data to server...");
      final alertData = await _uploadIntruderAlert(videoFile, position);
      
      if (alertData == null) {
        print("SecurityService: FAILED to upload intruder alert. Aborting.");
        return;
      }
      print("SecurityService: Intruder alert reported successfully: \${alertData['alert']['id']}");

      // 4. Record in Firestore (as backup/secondary log)
      await _recordInFirestore(alertData['alert']['videoUrl'], position, type: 'video');

    } catch (e, stack) {
      print("SecurityService: CRITICAL Error during intruder reporting: \$e");
      print("SecurityService: Stack trace: \$stack");
    } finally {
      _isCapturing = false;
    }
  }

  Future<File?> _recordVideoSilently({int durationSeconds = 5}) async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return null;

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await controller.initialize();
      await controller.startVideoRecording();
      
      await Future.delayed(Duration(seconds: durationSeconds));
      
      final XFile video = await controller.stopVideoRecording();
      await controller.dispose();

      return File(video.path);
    } catch (e) {
      print("SecurityService: Video recording error: \$e");
      if (controller != null) await controller.dispose();
      return null;
    }
  }

  Future<Map<String, dynamic>?> _uploadIntruderAlert(File file, Position? position) async {
    try {
      final tabletId = TabletService().tabletId ?? "unknown";
      final uri = Uri.parse(ServerConfig.intruderAlertEndpoint);
      final request = http.MultipartRequest('POST', uri);
      
      // Get device model info
      String deviceModel = 'Unknown';
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
      } catch (e) {
        print("SecurityService: Could not get device info: \$e");
      }

      // Add standard fields
      request.fields['tablet_id'] = tabletId;
      request.fields['latitude'] = position?.latitude.toString() ?? "0.0";
      request.fields['longitude'] = position?.longitude.toString() ?? "0.0";
      request.fields['reason'] = 'incorrect_pin';
      request.fields['timestamp'] = DateTime.now().toIso8601String();
      request.fields['device_model'] = deviceModel;
      request.fields['pin_entered'] = 'N/A';

      // Add video file
      final multipartFile = await http.MultipartFile.fromPath(
        'file', 
        file.path,
      );
      
      request.files.add(multipartFile);
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("SecurityService: Upload failed (\${response.statusCode}): \${response.body}");
        return null;
      }
    } catch (e) {
      print("SecurityService: Upload error: \$e");
      return null;
    }
  }

  Future<void> _recordInFirestore(String? mediaUrl, Position? position, {String type = 'video'}) async {
    try {
      final tabletId = TabletService().tabletId ?? "unknown";
      
      // Get device model info for Firestore record
      String deviceModel = 'Unknown';
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
      } catch (_) {}

      await FirebaseFirestore.instance.collection('intruder_alerts').add({
        'tablet_id': tabletId,
        'video_url': mediaUrl,  // SAS URL from server response
        'type': type,
        'latitude': position?.latitude ?? 0.0,
        'longitude': position?.longitude ?? 0.0,
        'timestamp': FieldValue.serverTimestamp(),
        'created_at': DateTime.now().toIso8601String(),
        'reason': 'incorrect_pin',
        'device_model': deviceModel,
        'pin_entered': 'N/A',
      });
      print("SecurityService: Alert recorded in Firestore");
    } catch (e) {
      print("SecurityService: Firestore Recording Error: \$e");
    }
  }
}
