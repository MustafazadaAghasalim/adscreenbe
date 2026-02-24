import 'dart:async';
import 'package:flutter/material.dart';

/// Survey Engine Widget for in-kiosk surveys.
/// Displays quick 1-3 question surveys during ad breaks
/// or between ad rotations. Results stored locally and synced.
class SurveyEngine extends StatefulWidget {
  final SurveyConfig config;
  final VoidCallback? onComplete;
  final void Function(Map<String, dynamic> results)? onSubmit;

  const SurveyEngine({
    super.key,
    required this.config,
    this.onComplete,
    this.onSubmit,
  });

  @override
  State<SurveyEngine> createState() => _SurveyEngineState();
}

class _SurveyEngineState extends State<SurveyEngine>
    with SingleTickerProviderStateMixin {
  int _currentQuestion = 0;
  final Map<String, dynamic> _answers = {};
  late AnimationController _slideController;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    // Auto-dismiss after timeout
    _timeoutTimer = Timer(
      Duration(seconds: widget.config.timeoutSeconds),
      _handleTimeout,
    );
  }

  void _handleTimeout() {
    widget.onComplete?.call();
  }

  void _answerQuestion(String questionId, dynamic answer) {
    setState(() {
      _answers[questionId] = answer;
      if (_currentQuestion < widget.config.questions.length - 1) {
        _slideController.reset();
        _currentQuestion++;
        _slideController.forward();
      } else {
        _submitSurvey();
      }
    });
  }

  void _submitSurvey() {
    widget.onSubmit?.call({
      'surveyId': widget.config.id,
      'answers': _answers,
      'timestamp': DateTime.now().toIso8601String(),
      'completedQuestions': _answers.length,
      'totalQuestions': widget.config.questions.length,
    });
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.config.questions[_currentQuestion];

    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _slideController,
            curve: Curves.easeOutCubic,
          )),
          child: Container(
            margin: const EdgeInsets.all(40),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress indicator
                Row(
                  children: List.generate(
                    widget.config.questions.length,
                    (i) => Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _currentQuestion
                              ? const Color(0xFF58A6FF)
                              : const Color(0xFF30363D),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Question
                Text(
                  question.text,
                  style: const TextStyle(
                    color: Color(0xFFF0F6FC),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Options
                ...question.options.map((option) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _answerQuestion(question.id, option),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF21262D),
                        foregroundColor: const Color(0xFFC9D1D9),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF30363D)),
                        ),
                      ),
                      child: Text(option, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                )),
                const SizedBox(height: 16),
                // Skip button
                TextButton(
                  onPressed: () => _answerQuestion(question.id, 'skipped'),
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Color(0xFF8B949E)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Survey configuration model.
class SurveyConfig {
  final String id;
  final List<SurveyQuestion> questions;
  final int timeoutSeconds;

  const SurveyConfig({
    required this.id,
    required this.questions,
    this.timeoutSeconds = 60,
  });

  factory SurveyConfig.fromJson(Map<String, dynamic> json) {
    return SurveyConfig(
      id: json['id'] ?? '',
      questions: (json['questions'] as List?)
              ?.map((q) => SurveyQuestion.fromJson(q))
              .toList() ??
          [],
      timeoutSeconds: json['timeoutSeconds'] ?? 60,
    );
  }
}

class SurveyQuestion {
  final String id;
  final String text;
  final List<String> options;

  const SurveyQuestion({
    required this.id,
    required this.text,
    required this.options,
  });

  factory SurveyQuestion.fromJson(Map<String, dynamic> json) {
    return SurveyQuestion(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      options: List<String>.from(json['options'] ?? []),
    );
  }
}
