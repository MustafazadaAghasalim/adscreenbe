import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import '../services/ad_service.dart';
import '../models/ad_model.dart';
import '../services/tablet_service.dart';
import '../services/chat_service.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/server_config.dart';
import '../admin_unlock_dialog.dart';
import 'modern_pin_dialog.dart'; // For ModernPinKey widget used by _RemoteLockOverlay
import '../services/security_service.dart';

// === NEW IMPORTS ===
import '../services/device_settings_service.dart';
import '../services/proof_of_play_service.dart';
import '../services/heatmap_telemetry_service.dart';
import '../services/isolate_prefetch_service.dart';
import 'ux_widgets.dart';

Future<void> toggleKiosk(bool enable) async {
  if (enable) {
    await startKioskMode();
  } else {
    await stopKioskMode();
  }
}

class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends ConsumerState<KioskScreen> {
  Timer? _adTimer;
  int _currentAdIndex = 0;
  List<Ad> _ads = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;
  String? _activeActionId; // NEW: Track currently active action from navbar
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Initialize Socket
    WidgetsBinding.instance.addPostFrameCallback((_) {
       AdService().initSocket();
       _focusNode.requestFocus();
       
       // Lock Volume to 50% (or whatever is current) to prevent user changes
       VolumeController().showSystemUI = false; // Hide the volume bar
    });
    
    // Listen for volume changes and reset them if they happen
    VolumeController().listener((volume) {
      // If we want to block volume changes, we can force it back
      // But for now, just hiding the UI is a good first step.
      // If the user really wants it BLOCKED:
      // VolumeController().setVolume(0.5); 
    });

    // Subscribe to Ad updates
    _subscription = AdService().adsStream.listen((ads) {
      if (mounted) {
        print("KioskScreen: Received ${ads.length} ads to play.");
        setState(() {
          _ads = ads;
          _isLoading = false;
        });
        
        // If we were waiting or list changed, ensure playback starts
        if (_adTimer == null || !_adTimer!.isActive) {
           _playNextAd();
        }
      }
    });
  }

  void _playNextAd() {
    _adTimer?.cancel();
    if (_ads.isEmpty) {
      // Retry or just wait for update
      return; 
    }

    if (_currentAdIndex >= _ads.length) _currentAdIndex = 0;
    final currentAd = _ads[_currentAdIndex];
    int duration = currentAd.duration;
    if (duration < 5) duration = 5; // Safety minimum

    print("KioskScreen: Playing ${currentAd.name} (${currentAd.type}) for ${duration}s");
    AdService().setCurrentCreative(currentAd.name);

    // === NEW: Log proof-of-play ===
    ProofOfPlayService().logPlay(
      adId: currentAd.id,
      adName: currentAd.name,
      tabletId: TabletService().tabletId ?? 'unknown',
      startedAt: DateTime.now(),
      durationSeconds: duration,
    );

    // === NEW: Set current ad for heatmap tracking ===
    HeatmapTelemetryService().setCurrentAd(currentAd.id);

    // === NEW: Prefetch upcoming ads in background ===
    if (_currentAdIndex + 1 < _ads.length) {
      final cacheDir = '/data/user/0/com.example.adscreen/cache';
      IsolatePrefetchService().prefetchUpcoming(_ads, _currentAdIndex, cacheDir);
    }

    _adTimer = Timer(Duration(seconds: duration), () {
      if (mounted) {
        setState(() {
          _currentAdIndex++;
        });
        _playNextAd();
      }
    });
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    _subscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _showPasswordDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (context) {
        return AdminUnlockDialog(
          correctPin: "3458",
          deviceId: TabletService().tabletId ?? "NDL-W09",
          onUnlock: () {
            Navigator.pop(context);
            _handleAdminUnlock();
          },
          onCancel: () {
            Navigator.pop(context);
          },
        );
      },
    );
  }

  Future<void> _handleAdminUnlock() async {
    const platform = MethodChannel('com.adscreen.kiosk/telemetry');
    try {
      await platform.invokeMethod('stopKiosk');
      await platform.invokeMethod('killApp');
    } catch (e) {
      print("Error stopping kiosk: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: TabletService().lockStatusStream,
      initialData: {'locked': TabletService().isLocked, 'pin': TabletService().unlockPin},
      builder: (context, snapshot) {
        final isLocked = snapshot.data?['locked'] ?? false;
        final pin = snapshot.data?['pin']?.toString();
        print("KioskScreen Build: isLocked=$isLocked, PIN=$pin");

        return KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (event) {
            // Block Volume Keys
            if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
                event.logicalKey == LogicalKeyboardKey.audioVolumeDown ||
                event.logicalKey == LogicalKeyboardKey.audioVolumeMute) {
              // We don't call any logic, effectively swallowing the key event
              // Note: On some Android devices, system volume UI might still appear
              // but the app won't react to it.
            }
          },
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              print("KioskScreen: Back navigation blocked.");
            },
            child: Stack(
              children: [
                Scaffold(
                  backgroundColor: Colors.black,
                  body: Column(
                    children: [
                      Expanded(
                        flex: 1080, 
                        child: _buildAdArea(),
                      ),
                      Expanded(
                        flex: 120,
                        child: BottomBar(
                          onAdminRequest: () => _showPasswordDialog(),
                          onActionTap: (actionId) {
                            setState(() {
                              _activeActionId = actionId;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLocked)
                  Positioned.fill(
                    child: _RemoteLockOverlay(expectedPin: pin),
                  ),
                if (_activeActionId != null)
                  Positioned.fill(
                    child: _ActionOverlay(
                      actionId: _activeActionId!,
                      onClose: () => setState(() => _activeActionId = null),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdArea() {
    if (_isLoading) {
      // === NEW: Shimmer loading instead of plain spinner ===
      return const AdShimmerLoader();
    }
    if (_ads.isEmpty) {
      return _buildDefaultBranding();
    }

    // Safety
    if (_currentAdIndex >= _ads.length) _currentAdIndex = 0;
    final ad = _ads[_currentAdIndex];

    // === NEW: Wrap with GestureDetector for heatmap touch tracking ===
    return GestureDetector(
      onTapDown: (details) {
        final size = MediaQuery.of(context).size;
        HeatmapTelemetryService().recordTouch(
          x: details.globalPosition.dx,
          y: details.globalPosition.dy,
          screenWidth: size.width,
          screenHeight: size.height,
        );
        // Haptic feedback on touch
        KioskHaptics.lightTap();
      },
      child: _AdContent(ad: ad),
    );
  }

  Widget _buildDefaultBranding() {
    return _AnimatedFallbackUI();
  }
}

class _AnimatedFallbackUI extends StatefulWidget {
  @override
  State<_AnimatedFallbackUI> createState() => _AnimatedFallbackUIState();
}

class _AnimatedFallbackUIState extends State<_AnimatedFallbackUI> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // Dynamic Background (Moving Gradients/Shapes)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _FallbackBackgroundPainter(_controller.value),
                );
              },
            ),
          ),
          
          // Glass Overlay for depth
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Pulsing Logo
                _PulsingLogo(),
                const SizedBox(height: 48),
                // Modern Typo
                const _AnimatedEmptyText(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingLogo extends StatefulWidget {
  @override
  State<_PulsingLogo> createState() => _PulsingLogoState();
}

class _PulsingLogoState extends State<_PulsingLogo> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.withOpacity(0.2),
              blurRadius: 100,
              spreadRadius: 2,
            )
          ],
        ),
        child: Image.asset(
          'assets/images/adscreen_logo.png', 
          height: 140, 
          errorBuilder: (_,__,___) => const Icon(Icons.tv, size: 100, color: Colors.white)
        ),
      ),
    );
  }
}

class _AnimatedEmptyText extends StatelessWidget {
  const _AnimatedEmptyText();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "ADSCREEN",
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 48,
            fontWeight: FontWeight.w900,
            letterSpacing: 12,
            fontFamily: 'Kinetika',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "No ads currently assigned",
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 20,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _FallbackBackgroundPainter extends CustomPainter {
  final double animationValue;
  _FallbackBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final center = Offset(size.width / 2, size.height / 2);
    
    // Draw moving glowing orbs
    final colors = [
      Colors.blueAccent.withOpacity(0.15),
      Colors.deepPurple.withOpacity(0.15),
      Colors.blue.withOpacity(0.1),
    ];

    for (var i = 0; i < 3; i++) {
      final angle = animationValue * 2 * pi + (i * pi * 2 / 3);
      final radius = 200.0 + (i * 50);
      final orbCenter = Offset(
        center.dx + cos(angle) * (size.width * 0.2),
        center.dy + sin(angle) * (size.height * 0.2),
      );
      
      paint.color = colors[i % colors.length];
      canvas.drawCircle(orbCenter, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FallbackBackgroundPainter oldDelegate) => true;
}

class _AdContent extends StatefulWidget {
  final Ad ad;
  const _AdContent({required this.ad});

  @override
  State<_AdContent> createState() => _AdContentState();
}

class _AdContentState extends State<_AdContent> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    if (widget.ad.type == 'video' && widget.ad.localPath != null) {
      _controller = VideoPlayerController.file(File(widget.ad.localPath!))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _controller!.play();
            _controller!.setLooping(false); // Controlled by parent timer usually, or ensure it plays once.
          }
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AdContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ad.id != widget.ad.id) {
       _controller?.dispose();
       _controller = null;
       _initializePlayer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ad.type == 'video') {
      if (_controller != null && _controller!.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    // Image
    if (widget.ad.localPath != null) {
      return Image.file(
        File(widget.ad.localPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_,__,___) => const Icon(Icons.broken_image, color: Colors.red),
      );
    }
    
    // Fallback if local path missing (shouldn't happen with new Service logic)
    return const Center(child: CircularProgressIndicator());
  }
}

/// Helper to parse hex color strings from backend settings.
Color _parseColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return fallback;
  }
}

class BottomBar extends StatelessWidget {
  final VoidCallback onAdminRequest;
  final Function(String) onActionTap;
  const BottomBar({
    super.key,
    required this.onAdminRequest,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: DeviceSettingsService().settingsStream,
      initialData: DeviceSettingsService().currentSettings,
      builder: (context, snapshot) {
        final settings = snapshot.data ?? {};

        // === Parse all navbar settings ===
        final Color bgColor = _parseColor(
            settings['navbarThemeColor']?.toString(), const Color(0xFF111111));
        final Color textColor = _parseColor(
            settings['navbarTextColor']?.toString(), Colors.white);
        final String qrUrl =
            settings['navbarQrUrl']?.toString() ?? 'https://adscreen.az';
        final String websiteText =
            settings['navbarWebsiteText']?.toString() ?? 'adscreen.az';
        final String phoneText =
            settings['navbarPhoneText']?.toString() ?? '+994 51 504 23 23';
        final Color timerTextColor = _parseColor(
            settings['navbarTimerTextColor']?.toString(), Colors.white);
        final Color timerBorderColor = _parseColor(
            settings['navbarTimerBorderColor']?.toString(),
            Colors.deepPurpleAccent);
        final int timerStrokeWidth =
            (settings['navbarTimerStrokeWidth'] as num?)?.toInt() ?? 5;
        final bool showAdscreenLogo =
            settings['navbarShowAdscreenLogo'] ?? true;
        final bool showMastercardLogo =
            settings['navbarShowMastercardLogo'] ?? true;
        final bool showVisaLogo =
            settings['navbarShowVisaLogo'] ?? false;
        final List<dynamic> rawButtons = settings['navbarButtons'] ?? [];

        return Container(
          height: 80,
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ─── LEFT: QR Code + Contact Info ───
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dynamic QR Code
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: QrImageView(
                        data: qrUrl,
                        version: QrVersions.auto,
                        size: 50,
                        backgroundColor: Colors.white,
                        errorStateBuilder: (ctx, err) => const Icon(
                            Icons.qr_code,
                            color: Colors.black,
                            size: 50),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Contact Info
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          websiteText,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'Kinetika',
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phoneText,
                          style: TextStyle(
                            color: textColor.withOpacity(0.85),
                            fontFamily: 'Kinetika',
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ─── CENTER: Logos + Custom Buttons ───
              Align(
                alignment: Alignment.center,
                child: _MastercardExitTrigger(
                  onAdminRequest: onAdminRequest,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Adscreen Logo
                      if (showAdscreenLogo)
                        Image.asset(
                          'assets/images/adscreen_logo_new.png',
                          height: 48,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Text(
                            "ADSCREEN",
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'Kinetika',
                            ),
                          ),
                        ),
                      if (showAdscreenLogo &&
                          (showMastercardLogo || showVisaLogo ||
                              rawButtons.isNotEmpty)) ...[
                        const SizedBox(width: 20),
                        Container(
                            width: 1,
                            height: 32,
                            color: textColor.withOpacity(0.4)),
                        const SizedBox(width: 20),
                      ],
                      // Mastercard Logo
                      if (showMastercardLogo)
                        Image.asset(
                          'assets/images/Mastercard-Logo.wine-2 1.png',
                          height: 36,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.credit_card,
                              size: 30,
                              color: Colors.orange),
                        ),
                      if (showMastercardLogo && (showVisaLogo || rawButtons.isNotEmpty))
                        const SizedBox(width: 16),
                      // Visa Logo
                      if (showVisaLogo)
                        Text(
                          'VISA',
                          style: TextStyle(
                            color: const Color(0xFF1A1F71),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            fontFamily: 'Kinetika',
                          ),
                        ),
                      if (showVisaLogo && rawButtons.isNotEmpty)
                        const SizedBox(width: 16),
                      // Dynamic Nav Buttons
                      ...rawButtons.map((btn) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                KioskHaptics.lightTap();
                                onActionTap(btn['actionId']?.toString() ?? 'custom');
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  color: textColor.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: textColor.withOpacity(0.1)),
                                ),
                                child: Text(
                                  btn['label']?.toString() ?? '',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Kinetika',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // ─── RIGHT: Volume + Timer ───
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const VolumeControlWidget(),
                    const SizedBox(width: 24),
                    CircularTimerWidget(
                      textColor: timerTextColor,
                      borderColor: timerBorderColor,
                      strokeWidth: timerStrokeWidth.toDouble(),
                    ),
                    const SizedBox(width: 12),
                    // Sync Pulse - flashes when data updates
                    _SyncPulseIcon(textColor: textColor),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class VolumeControlWidget extends StatefulWidget {
  const VolumeControlWidget({super.key});

  @override
  State<VolumeControlWidget> createState() => _VolumeControlWidgetState();
}

class _VolumeControlWidgetState extends State<VolumeControlWidget> {
  double _volume = 0.5;
  double _lastVolume = 0.5; // To restore after unmute

  @override
  void initState() {
    super.initState();
    VolumeController().getVolume().then((volume) {
      if (mounted) {
        setState(() {
          _volume = volume;
          if (volume > 0) _lastVolume = volume;
        });
      }
    });
    
    VolumeController().listener((volume) {
      if (mounted) {
        setState(() => _volume = volume);
      }
    });
  }

  @override
  void dispose() {
    VolumeController().removeListener();
    super.dispose();
  }

  void _toggleMute() {
    if (_volume > 0) {
      // Mute
      _lastVolume = _volume; // Save before muting
      VolumeController().setVolume(0);
      setState(() => _volume = 0);
    } else {
      // Unmute
      // If last volume was 0 (unexpected but possible), default to 0.5
      double target = _lastVolume > 0 ? _lastVolume : 0.5;
      VolumeController().setVolume(target);
      setState(() => _volume = target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleMute,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            Icon(
              _volume == 0 ? Icons.volume_off : Icons.volume_up, 
              color: Colors.white, 
              size: 28
            ),
            const SizedBox(width: 4),
            Text(
              _volume == 0 ? "Muted" : "${(_volume * 100).toInt()}%",
              style: const TextStyle(
                color: Colors.white, 
                fontFamily: 'Kinetika', 
                fontSize: 14,
                fontWeight: FontWeight.bold // Match new font weight
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class ChatDialog extends StatefulWidget {
  const ChatDialog({super.key});

  @override
  State<ChatDialog> createState() => _ChatDialogState();
}

class _ChatDialogState extends State<ChatDialog> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isSending = false;

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    final text = _controller.text;
    
    setState(() {
      _messages.add({"role": "user", "content": text});
      _isSending = true;
      _controller.clear();
    });

    final response = await ChatService().sendMessage(text);

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages.add({"role": "system", "content": response});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text("AI Assistant", style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (ctx, i) {
                  final msg = _messages[i];
                  final isUser = msg['role'] == "user";
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blue : Colors.grey[700],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(msg['content']!, style: const TextStyle(color: Colors.white)),
                    ),
                  );
                },
              ),
            ),
            if (_isSending) const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator()),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "Ask something...",
                      hintStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}

class CircularTimerWidget extends StatefulWidget {
  final Color textColor;
  final Color borderColor;
  final double strokeWidth;

  const CircularTimerWidget({
    super.key,
    this.textColor = Colors.white,
    this.borderColor = Colors.deepPurpleAccent,
    this.strokeWidth = 5,
  });

  @override
  State<CircularTimerWidget> createState() => _CircularTimerWidgetState();
}

class _CircularTimerWidgetState extends State<CircularTimerWidget> {
  Timer? _timer;
  int _secondsActive = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _secondsActive++;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_secondsActive ~/ 60).toString();
    final seconds = (_secondsActive % 60).toString().padLeft(2, '0');
    final progress = (_secondsActive % 60) / 60.0;

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Ring
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: widget.strokeWidth,
              color: widget.borderColor.withOpacity(0.2),
            ),
          ),
          // Progress Ring
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: widget.strokeWidth,
              color: widget.borderColor,
              backgroundColor: Colors.transparent,
            ),
          ),
          // Time Text
          Text(
            "$minutes:$seconds",
            style: TextStyle(
              color: widget.textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/** Reset ID removed per user request **/


class _MastercardExitTrigger extends StatefulWidget {
  final Widget child;
  final VoidCallback onAdminRequest;
  const _MastercardExitTrigger({required this.child, required this.onAdminRequest});

  @override
  State<_MastercardExitTrigger> createState() => _MastercardExitTriggerState();
}

class _MastercardExitTriggerState extends State<_MastercardExitTrigger> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        _timer = Timer(const Duration(seconds: 3), () {
          widget.onAdminRequest();
        });
      },
      onTapUp: (_) => _timer?.cancel(),
      onTapCancel: () => _timer?.cancel(),
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

// _KioskExitTrigger removed - no longer needed since exit is move to Mastercard logo

class _RemoteLockOverlay extends StatefulWidget {
  final String? expectedPin;
  const _RemoteLockOverlay({this.expectedPin});

  @override
  State<_RemoteLockOverlay> createState() => _RemoteLockOverlayState();
}

class _RemoteLockOverlayState extends State<_RemoteLockOverlay> with TickerProviderStateMixin {
  String _currentPin = "";
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _bgController;
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bgController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..forward();

    print("RemoteLockOverlay: Initialized with expected PIN: ${widget.expectedPin}");
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bgController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  String _getLabel(String text) => text;

  void _onKeyTap(String key) {
    if (_currentPin.length < 6) {
      setState(() => _currentPin += key);
      if (_currentPin == (widget.expectedPin ?? "000000")) {
        // Unlock on server
        _unlockOnServer();
      } else if (_currentPin.length == 6) {
        // NEW: Wrong PIN in Lock Overlay
        SecurityService().reportIntruder();
      }
    }
  }

  Future<void> _unlockOnServer() async {
    try {
      final response = await http.post(
        Uri.parse("${ServerConfig.baseUrl}/api/admin/lock_tablet"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'tablet_id': TabletService().tabletId,
          'locked': false
        }),
      );
      if (response.statusCode == 200) {
        // TabletService will receive the update via heartbeat or socket
        print("RemoteLock: Successfully unlocked via tablet");
      }
    } catch (e) {
      print("RemoteLock: Error unlocking: $e");
    }
  }

  void _onDelete() {
    if (_currentPin.isNotEmpty) {
      setState(() => _currentPin = _currentPin.substring(0, _currentPin.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entranceController,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Animated Background
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _LockBackgroundPainter(_bgController.value),
                  );
                },
              ),
            ),
            // Glassmorphism Overlay
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Pulsing Lock Icon
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.pinkAccent.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.pinkAccent.withOpacity(0.3),
                                      blurRadius: 30,
                                      spreadRadius: 2,
                                    )
                                  ],
                                ),
                                child: const Icon(Icons.lock_rounded, color: Colors.pinkAccent, size: 40),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _getLabel("DEVICE LOCKED"),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                shadows: [
                                  Shadow(color: Colors.pinkAccent, blurRadius: 10),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getLabel("Enter access code"),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // PIN Dots (6)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(6, (index) {
                                bool isActive = index < _currentPin.length;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.elasticOut,
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  width: isActive ? 12 : 8,
                                  height: isActive ? 12 : 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isActive ? Colors.pinkAccent : Colors.white.withOpacity(0.1),
                                    boxShadow: isActive ? [
                                      BoxShadow(
                                        color: Colors.pinkAccent.withOpacity(0.4),
                                        blurRadius: 6,
                                      )
                                    ] : [],
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 20),
                            // Number Pad
                            SizedBox(
                              width: 280,
                              child: GridView.count(
                                shrinkWrap: true,
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.5,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  ...["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((key) {
                                    return ModernPinKey(
                                      label: key, 
                                      onTap: () => _onKeyTap(key),
                                    );
                                  }),
                                  const SizedBox.shrink(),
                                  ModernPinKey(
                                    label: "0", 
                                    onTap: () => _onKeyTap("0"),
                                  ),
                                  _buildDeleteButton(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Informative Footer with Info and Upload
                  _buildEnhancedFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return GestureDetector(
      onTap: _onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white10),
        ),
        child: const Icon(Icons.backspace_rounded, color: Colors.white38, size: 22),
      ),
    );
  }

  Widget _buildEnhancedFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(Icons.sync_rounded, "SYNC", AdService().loopStatus),
              _buildInfoItem(Icons.cloud_upload_rounded, "UPLOAD", "Active"),
              _buildInfoItem(Icons.wifi_rounded, "SIGNAL", "Excellent"),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "ID: ${TabletService().tabletId}",
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 9, letterSpacing: 1.0),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security_rounded, color: Colors.pinkAccent.withOpacity(0.3), size: 10),
              const SizedBox(width: 6),
              Text(
                "SECURED BY ADSCREEN",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _LockBackgroundPainter extends CustomPainter {
  final double animationValue;
  _LockBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.pinkAccent.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    
    for (var i = 0; i < 3; i++) {
      final radius = (size.width * 0.3) + (i * 50) + (sin(animationValue * 2 * pi + i) * 20);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LockBackgroundPainter oldDelegate) => true;
}



/// NEW: Overlay shown when a navbar button is pressed
class _ActionOverlay extends StatelessWidget {
  final String actionId;
  final VoidCallback onClose;

  const _ActionOverlay({required this.actionId, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.95),
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getIconForAction(actionId),
            size: 120,
            color: Colors.white,
          ),
          const SizedBox(height: 32),
          Text(
            actionId.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "This component is being synchronized in real-time.\nMore interactive features coming soon.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 24),
          ),
          const SizedBox(height: 64),
          ElevatedButton(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white12,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white30),
              ),
            ),
            child: const Text("CLOSE & RESUME ADS",
                style: TextStyle(color: Colors.white, fontSize: 20)),
          ),
        ],
      ),
    );
  }

  IconData _getIconForAction(String id) {
    switch (id.toLowerCase()) {
      case 'games': return Icons.videogame_asset_outlined;
      case 'surveys': return Icons.poll_outlined;
      case 'interactivity': return Icons.touch_app_outlined;
      default: return Icons.apps_outlined;
    }
  }
}

/// NEW: A small glowing pulse that indicates settings were received
class _SyncPulseIcon extends StatefulWidget {
  final Color textColor;
  const _SyncPulseIcon({required this.textColor});

  @override
  State<_SyncPulseIcon> createState() => _SyncPulseIconState();
}

class _SyncPulseIconState extends State<_SyncPulseIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _sub = DeviceSettingsService().settingsStream.listen((_) {
      if (mounted) {
        _pulseController.forward(from: 0).then((_) {
          _pulseController.reverse();
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.textColor.withOpacity(0.2 + (0.8 * _pulseController.value)),
            boxShadow: [
              if (_pulseController.value > 0.1)
                BoxShadow(
                  color: widget.textColor.withOpacity(0.5 * _pulseController.value),
                  blurRadius: 10 * _pulseController.value,
                  spreadRadius: 2 * _pulseController.value,
                ),
            ],
          ),
        );
      },
    );
  }
}
