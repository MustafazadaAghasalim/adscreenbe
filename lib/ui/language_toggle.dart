import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// LanguageToggle — Sleek inline AZ / RU / EN toggle.
///
/// Changes the app's Locale state in real-time via EasyLocalization,
/// no restart required. Uses animated pill to indicate the active language.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  static const _languages = [
    _LangOption(code: 'az', label: 'AZ', flag: '🇦🇿'),
    _LangOption(code: 'ru', label: 'RU', flag: '🇷🇺'),
    _LangOption(code: 'en', label: 'EN', flag: '🇬🇧'),
  ];

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D14).withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _languages.map((lang) {
              final isActive =
                  currentLocale.languageCode == lang.code;

              return GestureDetector(
                onTap: () {
                  if (!isActive) {
                    context.setLocale(Locale(lang.code));
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isActive
                        ? const Color(0xFF8B5CF6).withOpacity(0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF8B5CF6).withOpacity(0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        lang.flag,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w400,
                          color: isActive
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                          letterSpacing: 1.5,
                          fontFamily: 'Kinetika',
                        ),
                        child: Text(lang.label),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _LangOption {
  final String code;
  final String label;
  final String flag;
  const _LangOption({
    required this.code,
    required this.label,
    required this.flag,
  });
}
