import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Audio Ducking Service.
/// Lowers system media volume during ad transitions,
/// then restores it for video ads with sound.
class AudioDuckingService {
  static final AudioDuckingService _instance = AudioDuckingService._internal();
  factory AudioDuckingService() => _instance;
  AudioDuckingService._internal();

  static const _channel = MethodChannel('com.example.adscreen/audio');

  int _savedVolume = 10;
  bool _isDucked = false;

  /// Duck audio (lower volume for transition).
  Future<void> duck() async {
    if (_isDucked) return;
    try {
      final currentVolume = await _channel.invokeMethod<int>('getVolume') ?? 10;
      _savedVolume = currentVolume;
      await _channel.invokeMethod('setVolume', {'volume': (currentVolume * 0.3).toInt()});
      _isDucked = true;
    } catch (e) {
      print("AudioDucking: Duck failed — $e");
    }
  }

  /// Restore audio to previous level.
  Future<void> restore() async {
    if (!_isDucked) return;
    try {
      await _channel.invokeMethod('setVolume', {'volume': _savedVolume});
      _isDucked = false;
    } catch (e) {
      print("AudioDucking: Restore failed — $e");
    }
  }

  /// Set volume to a specific level (0-15).
  Future<void> setVolume(int level) async {
    try {
      await _channel.invokeMethod('setVolume', {'volume': level.clamp(0, 15)});
    } catch (e) {
      print("AudioDucking: SetVolume failed — $e");
    }
  }

  /// Mute during transition then unmute.
  Future<void> transitionDuck(Duration duration) async {
    await duck();
    await Future.delayed(duration);
    await restore();
  }
}

/// Tabbed content view for interactive kiosk pages (Games, News, Taxi).
class TabbedContentView extends StatefulWidget {
  final List<KioskTab> tabs;

  const TabbedContentView({super.key, required this.tabs});

  @override
  State<TabbedContentView> createState() => _TabbedContentViewState();
}

class _TabbedContentViewState extends State<TabbedContentView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _autoSwitchTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.tabs.length,
      vsync: this,
    );

    // Auto-switch tabs every 30 seconds if no interaction
    _startAutoSwitch();
  }

  void _startAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _autoSwitchTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        final next = (_tabController.index + 1) % widget.tabs.length;
        _tabController.animateTo(next);
      }
    });
  }

  void _resetAutoSwitch() {
    _startAutoSwitch();
  }

  @override
  void dispose() {
    _autoSwitchTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _resetAutoSwitch,
      child: Column(
        children: [
          // Tab bar
          Container(
            color: const Color(0xFF161B22),
            child: TabBar(
              controller: _tabController,
              onTap: (_) => _resetAutoSwitch(),
              indicatorColor: const Color(0xFF58A6FF),
              labelColor: const Color(0xFF58A6FF),
              unselectedLabelColor: const Color(0xFF8B949E),
              tabs: widget.tabs.map((tab) => Tab(
                icon: Icon(tab.icon),
                text: tab.label,
              )).toList(),
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: widget.tabs.map((tab) => tab.content).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class KioskTab {
  final String label;
  final IconData icon;
  final Widget content;

  const KioskTab({
    required this.label,
    required this.icon,
    required this.content,
  });
}
