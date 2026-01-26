import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/security_service.dart';

class ModernPinDialog extends StatefulWidget {
  const ModernPinDialog({super.key});

  @override
  State<ModernPinDialog> createState() => _ModernPinDialogState();
}

class _ModernPinDialogState extends State<ModernPinDialog> with TickerProviderStateMixin {
  static const platform = MethodChannel('com.adscreen.kiosk/telemetry');
  String _currentPin = "";
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  
  // Info State
  String _deviceId = "Loading...";
  String _version = "1.0.0";
  int _batteryLevel = 0;

  @override
  void initState() {
    super.initState();
    
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 24.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
    
    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shakeController.reset();
        setState(() => _currentPin = "");
      }
    });

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _entranceController, curve: Curves.easeIn);
    _entranceController.forward();

    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();
    final battery = Battery();
    final batteryLevel = await battery.batteryLevel;

    String deviceId = "Unknown";
    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.model;
    }

    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _version = "${packageInfo.version}";
        _batteryLevel = batteryLevel;
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _onKeyTap(String key) {
    if (_currentPin.length < 4) {
      HapticFeedback.lightImpact();
      setState(() => _currentPin += key);
      if (_currentPin.length == 4) {
        _validatePin();
      }
    }
  }

  void _validatePin() {
    if (_currentPin == "1234") {
      HapticFeedback.mediumImpact();
      // Remove delay for immediate exit
      try {
        // Success: Exit Kiosk Mode Natively
        platform.invokeMethod('stopKiosk');
        // Fully exit the app immediately
        platform.invokeMethod('killApp');
        
        if (mounted) Navigator.pop(context);
      } catch (e) {
        print("Error stopping kiosk: $e");
        if (mounted) Navigator.pop(context);
      }
    } else {
      HapticFeedback.heavyImpact();
      _shakeController.forward();
      // Trigger the 5-second intruder video capture
      SecurityService().reportIntruder();
    }
  }

  void _onDelete() {
    if (_currentPin.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() => _currentPin = _currentPin.substring(0, _currentPin.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withOpacity(0.9),
                Colors.blueAccent.withOpacity(0.05),
                Colors.black.withOpacity(0.95),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Close Button
              Positioned(
                top: 30,
                right: 30,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
              
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Compact Info Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "SECURED DEVICE",
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _deviceId.toUpperCase(),
                          style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
                        ),
                        const SizedBox(height: 40),
                        
                        // PIN Pad Container
                        Container(
                          width: 320,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 40,
                                offset: const Offset(0, 20),
                              )
                            ],
                          ),
                          child: _buildPinArea(),
                        ),
                        
                        const SizedBox(height: 30),
                        // Version info
                        Text(
                          "ADSCREEN v$_version • BATTERY $_batteryLevel%",
                          style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinArea() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value * sin(_shakeController.value * pi * 4), 0),
          child: child,
        );
      },
      child: Column(
        children: [
          const Text(
            "AUTHORIZATION REQUIRED",
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),
          
          // PIN Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              bool isActive = index < _currentPin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: isActive ? 14 : 10,
                height: isActive ? 14 : 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Colors.blueAccent : Colors.white10,
                  boxShadow: isActive ? [
                    BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 8)
                  ] : [],
                ),
              );
            }),
          ),
          
          const SizedBox(height: 32),
          
          // Number Pad
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.2,
            children: [
              ...["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((key) {
                return ModernPinKey(label: key, onTap: () => _onKeyTap(key));
              }),
              const SizedBox.shrink(),
              ModernPinKey(label: "0", onTap: () => _onKeyTap("0")),
              _DeleteKey(onTap: _onDelete),
            ],
          ),
        ],
      ),
    );
  }
}

class ModernPinKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const ModernPinKey({super.key, required this.label, required this.onTap});

  @override
  State<ModernPinKey> createState() => _ModernPinKeyState();
}

class _ModernPinKeyState extends State<ModernPinKey> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteKey extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteKey({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.backspace_outlined, color: Colors.white38, size: 20),
    );
  }
}

