import 'dart:async';
import 'package:flutter/material.dart';

/// Lead Generation Form Overlay.
/// Displays a quick lead capture form (email, phone, name)
/// during interactive ad experiences. Data is stored locally
/// and batch-synced to the server.
class LeadGenOverlay extends StatefulWidget {
  final String adId;
  final String companyName;
  final String? promoText;
  final VoidCallback? onDismiss;
  final void Function(Map<String, String> leadData)? onSubmit;

  const LeadGenOverlay({
    super.key,
    required this.adId,
    required this.companyName,
    this.promoText,
    this.onDismiss,
    this.onSubmit,
  });

  @override
  State<LeadGenOverlay> createState() => _LeadGenOverlayState();
}

class _LeadGenOverlayState extends State<LeadGenOverlay>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  late AnimationController _animController;
  bool _submitted = false;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    // Auto-dismiss after 45 seconds
    _dismissTimer = Timer(const Duration(seconds: 45), () {
      widget.onDismiss?.call();
    });
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final leadData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'adId': widget.adId,
        'company': widget.companyName,
        'timestamp': DateTime.now().toIso8601String(),
      };

      widget.onSubmit?.call(leadData);
      setState(() => _submitted = true);

      // Dismiss after thank you
      Future.delayed(const Duration(seconds: 3), () {
        widget.onDismiss?.call();
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animController,
      child: Container(
        color: Colors.black.withOpacity(0.8),
        child: Center(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: _submitted ? _buildThankYou() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildThankYou() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF3FB950),
          size: 64,
        ),
        const SizedBox(height: 16),
        const Text(
          'Thank you!',
          style: TextStyle(
            color: Color(0xFFF0F6FC),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.companyName} will be in touch soon.',
          style: const TextStyle(
            color: Color(0xFF8B949E),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            widget.companyName,
            style: const TextStyle(
              color: Color(0xFF58A6FF),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.promoText ?? 'Get exclusive offers!',
            style: const TextStyle(
              color: Color(0xFFF0F6FC),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Name field
          _buildField(
            controller: _nameController,
            hint: 'Your name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 12),

          // Email field
          _buildField(
            controller: _emailController,
            hint: 'Email address',
            icon: Icons.email_outlined,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (!v.contains('@')) return 'Invalid email';
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Phone field
          _buildField(
            controller: _phoneController,
            hint: 'Phone (optional)',
            icon: Icons.phone_outlined,
          ),
          const SizedBox(height: 24),

          // Submit button
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Sign Up',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),

          // Dismiss
          TextButton(
            onPressed: widget.onDismiss,
            child: const Text(
              'No thanks',
              style: TextStyle(color: Color(0xFF8B949E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: const TextStyle(color: Color(0xFFC9D1D9)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF484F58)),
        prefixIcon: Icon(icon, color: const Color(0xFF8B949E)),
        filled: true,
        fillColor: const Color(0xFF0D1117),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF58A6FF)),
        ),
      ),
    );
  }
}
