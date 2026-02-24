import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/security_service.dart';

class AdminUnlockDialog extends StatefulWidget {
  final String correctPin;
  final String deviceId;
  final VoidCallback onUnlock;
  final VoidCallback onCancel;

  const AdminUnlockDialog({
    super.key,
    required this.correctPin,
    required this.deviceId,
    required this.onUnlock,
    required this.onCancel,
  });

  @override
  State<AdminUnlockDialog> createState() => _AdminUnlockDialogState();
}

class _AdminUnlockDialogState extends State<AdminUnlockDialog> {
  String _enteredPin = "";

  void _onKeyPress(String value) {
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += value;
      });
      HapticFeedback.lightImpact();
    }

    if (_enteredPin.length == 4) {
      _validatePin();
    }
  }

  void _onDelete() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _validatePin() async {
    if (_enteredPin == widget.correctPin) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      widget.onUnlock();
    } else {
      HapticFeedback.vibrate();
      SecurityService().reportIntruder();
      setState(() {
        _enteredPin = "";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Incorrect PIN"),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xE00F172A), // Solid dark background, no blur
      body: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              const Icon(Icons.lock_outline, color: Colors.blueAccent, size: 40),
              const SizedBox(height: 16),

              // Title
              const Text(
                "ADMIN ACCESS",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Device: ${widget.deviceId}",
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
              const SizedBox(height: 24),

              // PIN Dots - simple, no animation
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: isFilled ? Colors.blueAccent : const Color(0xFF334155),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),

              // Numpad - simplified
              _buildNumpad(),
              
              const SizedBox(height: 16),
              TextButton(
                onPressed: widget.onCancel,
                child: const Text("CANCEL", style: TextStyle(color: Color(0xFF64748B))),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return SizedBox(
      width: 260,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_keyBtn("1"), _keyBtn("2"), _keyBtn("3")],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_keyBtn("4"), _keyBtn("5"), _keyBtn("6")],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_keyBtn("7"), _keyBtn("8"), _keyBtn("9")],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 70),
              _keyBtn("0"),
              SizedBox(
                width: 70,
                height: 55,
                child: GestureDetector(
                  onTap: _onDelete,
                  child: const Center(
                    child: Icon(Icons.backspace_outlined, color: Colors.white54, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyBtn(String value) {
    return GestureDetector(
      onTap: () => _onKeyPress(value),
      child: Container(
        width: 70,
        height: 55,
        decoration: BoxDecoration(
          color: const Color(0xFF334155),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          value,
          style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
