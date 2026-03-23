import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Full-screen "Who Wants to Be a Millionaire" game widget.
/// Receives game data from Socket.io and renders the complete game experience.
class MillionaireGameScreen extends StatefulWidget {
  final Map<String, dynamic> gameData;
  final VoidCallback onGameEnd;
  final void Function(Map<String, dynamic> result) onResult;

  const MillionaireGameScreen({
    super.key,
    required this.gameData,
    required this.onGameEnd,
    required this.onResult,
  });

  @override
  State<MillionaireGameScreen> createState() => _MillionaireGameScreenState();
}

class _MillionaireGameScreenState extends State<MillionaireGameScreen>
    with TickerProviderStateMixin {
  // Game state
  int _currentLevel = 0;
  bool _gameOver = false;
  bool _won = false;
  String? _selectedOption;
  bool _answerRevealed = false;
  bool _walkedAway = false;

  // Timer
  int _timeLeft = 30;
  Timer? _timer;

  // Lifelines
  bool _fiftyFiftyUsed = false;
  bool _phoneUsed = false;
  bool _audienceUsed = false;
  Set<String> _eliminatedOptions = {};
  Map<String, int>? _audienceResults;
  String? _phoneHint;

  // Data from payload
  late List<Map<String, dynamic>> _questions;
  late List<String> _prizeLadder;
  late List<int> _safeHavens;
  late String _sessionId;

  // Animation
  late AnimationController _pulseController;
  late AnimationController _revealController;
  late Animation<double> _pulseAnim;

  // Question log for result reporting
  final List<Map<String, dynamic>> _questionsLog = [];

  @override
  void initState() {
    super.initState();
    final data = widget.gameData;
    _sessionId = data['session_id'] ?? '';
    _prizeLadder = List<String>.from(data['prize_ladder'] ?? []);
    _safeHavens = List<int>.from(data['safe_havens'] ?? [5, 10]);
    _questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _revealController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timeLeft = _currentLevel < 5 ? 30 : _currentLevel < 10 ? 45 : 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _timeLeft--; });
      if (_timeLeft <= 0) {
        t.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    _logAnswer(null, false);
    setState(() {
      _gameOver = true;
      _answerRevealed = true;
    });
    _endGame();
  }

  Map<String, dynamic> get _currentQuestion {
    if (_currentLevel < _questions.length) return _questions[_currentLevel];
    return {};
  }

  String get _correctOption => _currentQuestion['correct'] ?? 'A';

  void _selectOption(String option) {
    if (_answerRevealed || _gameOver || _eliminatedOptions.contains(option)) return;
    _timer?.cancel();

    setState(() { _selectedOption = option; });

    // Delay before revealing answer
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _revealController.forward(from: 0);
      final isCorrect = option == _correctOption;
      _logAnswer(option, isCorrect);

      setState(() { _answerRevealed = true; });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        if (isCorrect) {
          if (_currentLevel >= _questions.length - 1) {
            // Won the game!
            setState(() { _won = true; _gameOver = true; });
            _endGame();
          } else {
            _nextQuestion();
          }
        } else {
          setState(() { _gameOver = true; });
          _endGame();
        }
      });
    });
  }

  void _nextQuestion() {
    setState(() {
      _currentLevel++;
      _selectedOption = null;
      _answerRevealed = false;
      _eliminatedOptions = {};
      _audienceResults = null;
      _phoneHint = null;
    });
    _startTimer();
  }

  void _logAnswer(String? chosen, bool correct) {
    _questionsLog.add({
      'level': _currentLevel,
      'question': _currentQuestion['text'],
      'chosen': chosen,
      'correct': _correctOption,
      'is_correct': correct,
      'time_remaining': _timeLeft,
    });
  }

  void _endGame() {
    _timer?.cancel();
    // Determine final prize level
    int finalLevel = _walkedAway || _won ? _currentLevel + 1 : 0;
    if (!_walkedAway && !_won) {
      // Find last safe haven passed
      for (final haven in _safeHavens.reversed) {
        if (_currentLevel >= haven) {
          finalLevel = haven;
          break;
        }
      }
    }

    final lifelinesUsed = <String>[];
    if (_fiftyFiftyUsed) lifelinesUsed.add('50:50');
    if (_phoneUsed) lifelinesUsed.add('phone');
    if (_audienceUsed) lifelinesUsed.add('audience');

    widget.onResult({
      'session_id': _sessionId,
      'final_level': finalLevel,
      'walked_away': _walkedAway,
      'lifelines_used': lifelinesUsed,
      'questions_log': _questionsLog,
    });

    // Auto-close after delay
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) widget.onGameEnd();
    });
  }

  void _walkAway() {
    _timer?.cancel();
    setState(() {
      _walkedAway = true;
      _gameOver = true;
    });
    _endGame();
  }

  // === LIFELINES ===

  void _useFiftyFifty() {
    if (_fiftyFiftyUsed || _answerRevealed) return;
    setState(() { _fiftyFiftyUsed = true; });

    final correct = _correctOption;
    final wrong = ['A', 'B', 'C', 'D'].where((o) => o != correct).toList()..shuffle();
    setState(() {
      _eliminatedOptions = {wrong[0], wrong[1]};
    });
  }

  void _usePhoneAFriend() {
    if (_phoneUsed || _answerRevealed) return;
    setState(() { _phoneUsed = true; });

    final correct = _correctOption;
    // 80% chance of correct answer
    final rand = Random();
    String hint;
    if (rand.nextDouble() < 0.8) {
      hint = correct;
    } else {
      final wrong = ['A', 'B', 'C', 'D'].where((o) => o != correct).toList()..shuffle();
      hint = wrong.first;
    }
    final options = _currentQuestion['options'] as Map<String, dynamic>? ?? {};
    setState(() {
      _phoneHint = '"I think it\'s $hint — ${options[hint]}"';
    });
  }

  void _useAskAudience() {
    if (_audienceUsed || _answerRevealed) return;
    setState(() { _audienceUsed = true; });

    final correct = _correctOption;
    final rand = Random();
    final correctPct = 40 + rand.nextInt(40); // 40–79%
    int remaining = 100 - correctPct;
    final results = <String, int>{correct: correctPct};

    for (final opt in ['A', 'B', 'C', 'D']) {
      if (opt == correct) continue;
      if (_eliminatedOptions.contains(opt)) {
        results[opt] = 0;
        continue;
      }
      final share = remaining > 0 ? rand.nextInt(remaining + 1) : 0;
      results[opt] = share;
      remaining -= share;
    }
    // Give remainder to a random wrong option
    final nonCorrect = results.keys.where((k) => k != correct && !_eliminatedOptions.contains(k)).toList();
    if (nonCorrect.isNotEmpty && remaining > 0) {
      results[nonCorrect.first] = (results[nonCorrect.first] ?? 0) + remaining;
    }

    setState(() { _audienceResults = results; });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0a0e27), Color(0xFF1a1a3e), Color(0xFF0d0d2b)],
        ),
      ),
      child: SafeArea(
        child: _gameOver ? _buildGameOverScreen() : _buildGameScreen(),
      ),
    );
  }

  Widget _buildGameScreen() {
    final q = _currentQuestion;
    final options = q['options'] as Map<String, dynamic>? ?? {};
    final imageUrl = q['image_url'] as String?;
    final prize = _currentLevel < _prizeLadder.length
        ? _prizeLadder[_currentLevel]
        : '???';

    return Column(
      children: [
        // Top bar: timer + level + prize
        _buildTopBar(prize),
        const SizedBox(height: 8),

        // Question image (if any)
        if (imageUrl != null && imageUrl.isNotEmpty)
          Container(
            height: 120,
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withAlpha(80)),
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              ),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

        // Question text
        Expanded(
          flex: 3,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1e3a5f), Color(0xFF0f2847)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withAlpha(120), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withAlpha(30),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                q['text'] ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),

        // Phone hint
        if (_phoneHint != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _phoneHint!,
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Audience graph
        if (_audienceResults != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
            child: _buildAudienceGraph(),
          ),

        // Answer options (2x2 grid)
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildOptionButton('A', options['A'] ?? '')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildOptionButton('B', options['B'] ?? '')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildOptionButton('C', options['C'] ?? '')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildOptionButton('D', options['D'] ?? '')),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Bottom: Lifelines + Walk Away
        _buildBottomBar(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTopBar(String prize) {
    final timerColor = _timeLeft <= 5
        ? Colors.red
        : _timeLeft <= 10
            ? Colors.orange
            : Colors.amber;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          // Timer
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) => Transform.scale(
              scale: _timeLeft <= 5 ? _pulseAnim.value : 1.0,
              child: child,
            ),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: timerColor, width: 3),
                color: timerColor.withAlpha(30),
              ),
              child: Center(
                child: Text(
                  '$_timeLeft',
                  style: TextStyle(
                    color: timerColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Level & Prize
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'QUESTION ${_currentLevel + 1}/${_questions.length}',
                style: TextStyle(
                  color: Colors.white.withAlpha(140),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    prize,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionButton(String label, String text) {
    final isEliminated = _eliminatedOptions.contains(label);
    final isSelected = _selectedOption == label;
    final isCorrect = label == _correctOption;

    Color bgColor;
    Color borderColor;
    double opacity = 1.0;

    if (isEliminated) {
      bgColor = Colors.transparent;
      borderColor = Colors.white10;
      opacity = 0.2;
    } else if (_answerRevealed) {
      if (isCorrect) {
        bgColor = const Color(0xFF22c55e).withAlpha(60);
        borderColor = const Color(0xFF22c55e);
      } else if (isSelected) {
        bgColor = const Color(0xFFef4444).withAlpha(60);
        borderColor = const Color(0xFFef4444);
      } else {
        bgColor = const Color(0xFF1e3a5f).withAlpha(120);
        borderColor = Colors.white24;
      }
    } else if (isSelected) {
      bgColor = Colors.amber.withAlpha(40);
      borderColor = Colors.amber;
    } else {
      bgColor = const Color(0xFF1e3a5f).withAlpha(180);
      borderColor = Colors.amber.withAlpha(80);
    }

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: isEliminated ? null : () => _selectOption(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: borderColor.withAlpha(40),
                  border: Border.all(color: borderColor),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: borderColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_answerRevealed && isCorrect)
                const Icon(Icons.check_circle, color: Color(0xFF22c55e), size: 24),
              if (_answerRevealed && isSelected && !isCorrect)
                const Icon(Icons.cancel, color: Color(0xFFef4444), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLifelineButton(
            icon: Icons.looks_two,
            label: '50:50',
            used: _fiftyFiftyUsed,
            onTap: _useFiftyFifty,
          ),
          _buildLifelineButton(
            icon: Icons.phone_in_talk,
            label: 'Phone',
            used: _phoneUsed,
            onTap: _usePhoneAFriend,
          ),
          _buildLifelineButton(
            icon: Icons.people,
            label: 'Audience',
            used: _audienceUsed,
            onTap: _useAskAudience,
          ),
          const SizedBox(width: 16),
          // Walk away button
          GestureDetector(
            onTap: _walkAway,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withAlpha(120)),
                color: Colors.red.withAlpha(20),
              ),
              child: const Text(
                'WALK AWAY',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifelineButton({
    required IconData icon,
    required String label,
    required bool used,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: used ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: used ? 0.25 : 1.0,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: used ? Colors.white24 : Colors.amber.withAlpha(120),
            ),
            color: used ? Colors.transparent : Colors.amber.withAlpha(15),
          ),
          child: Column(
            children: [
              Icon(icon, color: used ? Colors.white30 : Colors.amber, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: used ? Colors.white30 : Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudienceGraph() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ['A', 'B', 'C', 'D'].map((opt) {
          final pct = _audienceResults?[opt] ?? 0;
          final isElim = _eliminatedOptions.contains(opt);
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$pct%',
                style: TextStyle(
                  color: isElim ? Colors.white24 : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 28,
                height: max(4, pct * 0.3),
                decoration: BoxDecoration(
                  color: isElim ? Colors.white10 : Colors.blueAccent.withAlpha(180),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 2),
              Text(opt, style: TextStyle(color: isElim ? Colors.white24 : Colors.white54, fontSize: 10)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGameOverScreen() {
    final isWin = _won;
    final isWalkAway = _walkedAway;

    int prizeLevel = 0;
    if (isWin) {
      prizeLevel = _questions.length;
    } else if (isWalkAway) {
      prizeLevel = _currentLevel; // walked away before answering current
    } else {
      for (final haven in _safeHavens.reversed) {
        if (_currentLevel >= haven) {
          prizeLevel = haven;
          break;
        }
      }
    }
    final prizeText = prizeLevel > 0 && prizeLevel <= _prizeLadder.length
        ? _prizeLadder[prizeLevel - 1]
        : '0';

    final title = isWin
        ? '🎉 MILLIONAIRE!'
        : isWalkAway
            ? '🚶 WALKED AWAY'
            : '❌ GAME OVER';

    final subtitle = isWin
        ? 'You answered all questions correctly!'
        : isWalkAway
            ? 'Smart choice — you keep your winnings!'
            : 'Better luck next time!';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: isWin ? Colors.amber : isWalkAway ? Colors.orange : Colors.redAccent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isWin
                    ? [const Color(0xFFf59e0b), const Color(0xFFd97706)]
                    : [const Color(0xFF1e3a5f), const Color(0xFF0f2847)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withAlpha(120), width: 2),
            ),
            child: Column(
              children: [
                Text(
                  'FINAL PRIZE',
                  style: TextStyle(
                    color: Colors.white.withAlpha(160),
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  prizeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Reached level ${_currentLevel + 1} of ${_questions.length}',
            style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14),
          ),
          const SizedBox(height: 32),
          Text(
            'Returning to ads...',
            style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
