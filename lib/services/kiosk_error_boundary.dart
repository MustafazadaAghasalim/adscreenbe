import 'package:flutter/material.dart';

/// Custom Error Boundary — replaces the default red error screen
/// with a branded, kiosk-appropriate error display.
/// Features:
///   - Branded error screen with AdScreen logo feel
///   - Auto-recovery attempt after timeout
///   - Logs error details for remote diagnostics
class KioskErrorBoundary {
  static void install() {
    // Replace the default error widget
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return _KioskErrorWidget(details: details);
    };

    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logError(details);
    };

    print("ErrorBoundary: Installed branded error screen.");
  }

  static void _logError(FlutterErrorDetails details) {
    print("ErrorBoundary: ${details.exceptionAsString()}");
    print("ErrorBoundary: Stack: ${details.stack}");
    // Could integrate with ProofOfPlayService or TelemetryService
  }
}

class _KioskErrorWidget extends StatefulWidget {
  final FlutterErrorDetails details;

  const _KioskErrorWidget({required this.details});

  @override
  State<_KioskErrorWidget> createState() => _KioskErrorWidgetState();
}

class _KioskErrorWidgetState extends State<_KioskErrorWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  int _countdown = 10;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Auto-recovery countdown
    _startCountdown();
  }

  void _startCountdown() async {
    for (int i = 10; i > 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() => _countdown = i - 1);
      }
    }
    // Attempt recovery by rebuilding
    if (mounted) {
      _attemptRecovery();
    }
  }

  void _attemptRecovery() {
    // Navigate to root or trigger rebuild
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      print("ErrorBoundary: Recovery navigation failed: $e");
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated pulse icon
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.4 + (_pulseController.value * 0.6),
                  child: const Icon(
                    Icons.tv,
                    size: 80,
                    color: Color(0xFF58A6FF),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'ADSCREEN',
              style: TextStyle(
                color: Color(0xFF58A6FF),
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Refreshing experience in $_countdown s...',
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 40),
            // Subtle error info (for debugging)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
              child: Text(
                widget.details.exceptionAsString().length > 100
                    ? widget.details.exceptionAsString().substring(0, 100)
                    : widget.details.exceptionAsString(),
                style: const TextStyle(
                  color: Color(0xFF484F58),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
