import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

class PowerWakeWrapper extends StatefulWidget {
  final Widget child;

  const PowerWakeWrapper({
    super.key,
    required this.child,
  });

  @override
  State<PowerWakeWrapper> createState() => _PowerWakeWrapperState();
}

class _PowerWakeWrapperState extends State<PowerWakeWrapper> {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  bool _isScreenOff = false;

  @override
  void initState() {
    super.initState();
    _initializeBattery();
  }

  Future<void> _initializeBattery() async {
    // Check initial state
    try {
      final state = await _battery.batteryState;
      _updateScreenState(state);
    } catch (e) {
      debugPrint('Error getting battery state: $e');
    }

    // Listen for changes
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      _updateScreenState(state);
    });
  }

  void _updateScreenState(BatteryState state) {
    // If charging or full, screen is ON (active).
    // If discharging (not connected), screen is OFF (black overlay).
    // Treat 'unknown' as ON to prevent lockouts.
    final shouldBeOn = state == BatteryState.charging || 
                       state == BatteryState.full || 
                       state == BatteryState.unknown;
    
    if (mounted) {
      setState(() {
        _isScreenOff = !shouldBeOn;
      });
    }
  }

  @override
  void dispose() {
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main App Content
        widget.child,
        
        // Black Overlay (Fake Screen Off)
        if (_isScreenOff)
          Positioned.fill(
            child: GestureDetector(
              // Safety: Long press to temporarily wake up (for maintenance)
              onLongPress: () {
                setState(() {
                  _isScreenOff = false;
                });
                // Re-check battery after 10 seconds
                Future.delayed(const Duration(seconds: 10), () async {
                  if (mounted) {
                    final state = await _battery.batteryState;
                    _updateScreenState(state);
                  }
                });
              },
              child: Container(
                color: Colors.black,
                child: const Center(
                  // Optional: Show a charging icon or text if needed, 
                  // but user requested "turn off screen" behavior.
                ),
              ),
            ),
          ),
      ],
    );
  }
}
