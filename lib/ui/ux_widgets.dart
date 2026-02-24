import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer / Skeleton loading widgets for AdScreen kiosk.
/// Used when ads are loading, transitioning, or empty states.

/// Full-screen shimmer loader for ad content area.
class AdShimmerLoader extends StatelessWidget {
  const AdShimmerLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFF21262D),
        highlightColor: const Color(0xFF30363D),
        child: Column(
          children: [
            // Main ad area shimmer
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            // Bottom bar shimmer
            Container(
              height: 60,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small shimmer placeholder for list items or thumbnails.
class ThumbnailShimmer extends StatelessWidget {
  final double width;
  final double height;

  const ThumbnailShimmer({
    super.key,
    this.width = 120,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF21262D),
      highlightColor: const Color(0xFF30363D),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Skeleton loader for text content lines.
class TextSkeletonLoader extends StatelessWidget {
  final int lines;
  final double lineHeight;

  const TextSkeletonLoader({
    super.key,
    this.lines = 3,
    this.lineHeight = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF21262D),
      highlightColor: const Color(0xFF30363D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(lines, (index) {
          final widthFactor = index == lines - 1 ? 0.6 : 0.9;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              child: Container(
                height: lineHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Animated pulse CTA indicator — a glowing ring around interactive elements.
class PulseCTAIndicator extends StatefulWidget {
  final Widget child;
  final Color color;
  final double maxScale;

  const PulseCTAIndicator({
    super.key,
    required this.child,
    this.color = const Color(0xFF58A6FF),
    this.maxScale = 1.15,
  });

  @override
  State<PulseCTAIndicator> createState() => _PulseCTAIndicatorState();
}

class _PulseCTAIndicatorState extends State<PulseCTAIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * (widget.maxScale - 1.0));
        return Stack(
          alignment: Alignment.center,
          children: [
            // Glow ring
            Transform.scale(
              scale: scale,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withOpacity(0.3 * (1 - _controller.value)),
                    width: 3,
                  ),
                ),
                child: Opacity(
                  opacity: 0,
                  child: widget.child,
                ),
              ),
            ),
            // Actual child
            widget.child,
          ],
        );
      },
    );
  }
}

/// Dark mode context-aware theme that switches based on time of day.
/// Uses Baku timezone (UTC+4) for sunset/sunrise calculations.
class KioskTheme {
  static const _bakuUtcOffset = 4;

  /// Get current theme mode based on Baku time.
  static bool isDarkMode() {
    final bakuNow = DateTime.now().toUtc().add(const Duration(hours: _bakuUtcOffset));
    final hour = bakuNow.hour;
    // Dark mode between 7 PM and 7 AM
    return hour >= 19 || hour < 7;
  }

  static ThemeData get currentTheme => isDarkMode() ? darkTheme : lightTheme;

  static final darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0D1117),
    primaryColor: const Color(0xFF58A6FF),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF58A6FF),
      secondary: Color(0xFF3FB950),
      surface: Color(0xFF161B22),
      error: Color(0xFFF85149),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: Color(0xFFF0F6FC), fontSize: 28, fontWeight: FontWeight.bold),
      bodyLarge: TextStyle(color: Color(0xFFC9D1D9), fontSize: 16),
      bodyMedium: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
    ),
  );

  static final lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF6F8FA),
    primaryColor: const Color(0xFF0969DA),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF0969DA),
      secondary: Color(0xFF1A7F37),
      surface: Color(0xFFFFFFFF),
      error: Color(0xFFCF222E),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: Color(0xFF1F2328), fontSize: 28, fontWeight: FontWeight.bold),
      bodyLarge: TextStyle(color: Color(0xFF1F2328), fontSize: 16),
      bodyMedium: TextStyle(color: Color(0xFF656D76), fontSize: 14),
    ),
  );
}

/// Haptic feedback helper for kiosk touch interactions.
class KioskHaptics {
  static void lightTap() {
    HapticFeedback.lightImpact();
  }

  static void mediumTap() {
    HapticFeedback.mediumImpact();
  }

  static void heavyTap() {
    HapticFeedback.heavyImpact();
  }

  static void selection() {
    HapticFeedback.selectionClick();
  }
}

/// Hero transition wrapper for smooth ad transitions.
class AdHeroTransition extends StatelessWidget {
  final String tag;
  final Widget child;

  const AdHeroTransition({
    super.key,
    required this.tag,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'ad_$tag',
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}
