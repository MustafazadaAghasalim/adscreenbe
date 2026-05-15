import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Geofencing Trigger Service.
/// Uses device GPS/network location to trigger location-based
/// ad content or adjust ad scheduling based on geofence zones.
/// Primarily for mobile kiosks (vehicles, pop-up displays).
class GeofencingService {
  static final GeofencingService _instance = GeofencingService._internal();
  factory GeofencingService() => _instance;
  GeofencingService._internal();

  Timer? _locationTimer;
  Position? _lastPosition;
  final List<Geofence> _fences = [];
  final _triggerController = StreamController<GeofenceTrigger>.broadcast();

  Stream<GeofenceTrigger> get triggers => _triggerController.stream;

  /// Belgium default zones — major cities & airport.
  static final List<Geofence> defaultBelgiumZones = [
    Geofence(
      id: 'brussels_center',
      name: 'Brussels City Center',
      lat: 50.8503,
      lng: 4.3517,
      radiusMeters: 2000,
    ),
    Geofence(
      id: 'antwerp_center',
      name: 'Antwerp City Center',
      lat: 51.2194,
      lng: 4.4025,
      radiusMeters: 2000,
    ),
    Geofence(
      id: 'brussels_airport',
      name: 'Brussels Airport (Zaventem)',
      lat: 50.9014,
      lng: 4.4844,
      radiusMeters: 3000,
    ),
  ];

  Future<void> start({List<Geofence>? customFences}) async {
    _fences.clear();
    _fences.addAll(customFences ?? defaultBelgiumZones);

    // Check permissions
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Geofencing: Location services disabled.");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print("Geofencing: Permission denied.");
        return;
      }
    }

    // Check location every 60 seconds
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkLocation());
    _checkLocation(); // Initial check

    print("Geofencing: Started with ${_fences.length} zones.");
  }

  Future<void> _checkLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      _lastPosition = position;

      for (final fence in _fences) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          fence.lat,
          fence.lng,
        );

        final wasInside = fence.isInside;
        fence.isInside = distance <= fence.radiusMeters;

        if (!wasInside && fence.isInside) {
          // Entered zone
          _triggerController.add(GeofenceTrigger(
            fence: fence,
            type: GeofenceEventType.enter,
            position: position,
            distance: distance,
          ));
          print("Geofencing: ENTERED ${fence.name} (${distance.toStringAsFixed(0)}m)");
        } else if (wasInside && !fence.isInside) {
          // Exited zone
          _triggerController.add(GeofenceTrigger(
            fence: fence,
            type: GeofenceEventType.exit,
            position: position,
            distance: distance,
          ));
          print("Geofencing: EXITED ${fence.name} (${distance.toStringAsFixed(0)}m)");
        }
      }
    } catch (e) {
      print("Geofencing: Location check error — $e");
    }
  }

  /// Get current position
  Position? get lastPosition => _lastPosition;

  /// Check if device is in any geofence
  List<Geofence> getActiveFences() {
    return _fences.where((f) => f.isInside).toList();
  }

  void stop() {
    _locationTimer?.cancel();
    _triggerController.close();
  }
}

class Geofence {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;
  bool isInside;

  Geofence({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.isInside = false,
  });
}

class GeofenceTrigger {
  final Geofence fence;
  final GeofenceEventType type;
  final Position position;
  final double distance;

  GeofenceTrigger({
    required this.fence,
    required this.type,
    required this.position,
    required this.distance,
  });
}

enum GeofenceEventType { enter, exit }
