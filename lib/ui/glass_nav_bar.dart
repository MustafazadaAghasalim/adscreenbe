import 'dart:ui';
import 'package:flutter/material.dart';

/// GlassNavigationBar — Premium frosted-glass bottom nav for the kiosk.
///
/// Dark glassmorphism aesthetic with monochrome icons, animated indicator pill,
/// and smooth transitions. Replaces the old colorful BottomBar.
class GlassNavigationBar extends StatefulWidget {
  final VoidCallback onAdminRequest;
  final Function(String) onActionTap;
  final int selectedIndex;
  final Function(int) onIndexChanged;

  const GlassNavigationBar({
    super.key,
    required this.onAdminRequest,
    required this.onActionTap,
    this.selectedIndex = 0,
    required this.onIndexChanged,
  });

  @override
  State<GlassNavigationBar> createState() => _GlassNavigationBarState();
}

class _GlassNavigationBarState extends State<GlassNavigationBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _indicatorController;
  late Animation<double> _indicatorAnimation;
  int _previousIndex = 0;

  // 5-tap admin escape trigger
  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  static const _navItems = [
    _NavItem(icon: Icons.play_circle_outline_rounded, label: 'Ads'),
    _NavItem(icon: Icons.videocam_outlined, label: 'Live View'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Telemetry'),
    _NavItem(icon: Icons.tune_rounded, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _indicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _indicatorAnimation = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _indicatorController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(covariant GlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _animateIndicator(oldWidget.selectedIndex, widget.selectedIndex);
    }
  }

  void _animateIndicator(int from, int to) {
    _indicatorAnimation = Tween<double>(
      begin: from.toDouble(),
      end: to.toDouble(),
    ).animate(CurvedAnimation(
      parent: _indicatorController,
      curve: Curves.easeOutCubic,
    ));
    _indicatorController.forward(from: 0);
    _previousIndex = to;
  }

  void _handleLogoTap() {
    final now = DateTime.now();
    if (_lastLogoTap != null &&
        now.difference(_lastLogoTap!).inMilliseconds > 2000) {
      _logoTapCount = 0;
    }
    _lastLogoTap = now;
    _logoTapCount++;
    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      widget.onAdminRequest();
    }
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D14).withOpacity(0.85),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.06),
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // ─── LEFT: Logo (admin escape trigger) ───
                GestureDetector(
                  onTap: _handleLogoTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/adscreen_logo_new.png',
                        height: 36,
                        errorBuilder: (_, __, ___) => Text(
                          'ADSCREEN',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            fontFamily: 'Kinetika',
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 1,
                        height: 28,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 20),

                // ─── CENTER: Nav Items with animated indicator ───
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth / _navItems.length;
                      return Stack(
                        children: [
                          // Animated indicator pill
                          AnimatedBuilder(
                            animation: _indicatorAnimation,
                            builder: (context, _) {
                              final position = _indicatorAnimation.value;
                              return Positioned(
                                left: position * itemWidth +
                                    (itemWidth - 64) / 2,
                                bottom: 6,
                                child: Container(
                                  width: 64,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF8B5CF6),
                                        Color(0xFF6366F1),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8B5CF6)
                                            .withOpacity(0.4),
                                        blurRadius: 12,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          // Nav items
                          Row(
                            children: List.generate(_navItems.length, (index) {
                              final item = _navItems[index];
                              final isSelected =
                                  widget.selectedIndex == index;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    widget.onIndexChanged(index);
                                    if (index > 0) {
                                      widget.onActionTap(item.label
                                          .toLowerCase()
                                          .replaceAll(' ', '_'));
                                    }
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            color: isSelected
                                                ? const Color(0xFF8B5CF6)
                                                    .withOpacity(0.15)
                                                : Colors.transparent,
                                          ),
                                          child: Icon(
                                            item.icon,
                                            size: 22,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.white
                                                    .withOpacity(0.35),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        AnimatedDefaultTextStyle(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.white
                                                    .withOpacity(0.35),
                                            letterSpacing: 1.2,
                                            fontFamily: 'Kinetika',
                                          ),
                                          child: Text(
                                            item.label.toUpperCase(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(width: 20),

                // ─── RIGHT: Status indicators ───
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    const SizedBox(width: 16),
                    // Connection dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF34D399),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF34D399).withOpacity(0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        fontFamily: 'Kinetika',
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Clock
                    StreamBuilder(
                      stream: Stream.periodic(
                        const Duration(seconds: 30),
                        (_) => DateTime.now(),
                      ),
                      builder: (context, snapshot) {
                        final now = snapshot.data ?? DateTime.now();
                        return Text(
                          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Kinetika',
                            letterSpacing: 1,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
