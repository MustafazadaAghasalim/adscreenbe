import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR Code Generator Widget for Ad Engagement.
/// Generates on-screen QR codes that link to advertiser pages,
/// promo codes, app downloads, or survey URLs.
class AdQRCodeWidget extends StatelessWidget {
  final String url;
  final double size;
  final String? label;
  final Color foregroundColor;
  final Color backgroundColor;

  const AdQRCodeWidget({
    super.key,
    required this.url,
    this.size = 150,
    this.label,
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: url,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0D1117),
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: TextStyle(
              color: foregroundColor.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// QR overlay that appears on interactive ads.
class QROverlay extends StatefulWidget {
  final String url;
  final String callToAction;
  final Duration displayDuration;
  final VoidCallback? onDismiss;

  const QROverlay({
    super.key,
    required this.url,
    this.callToAction = 'Scan for more info',
    this.displayDuration = const Duration(seconds: 15),
    this.onDismiss,
  });

  @override
  State<QROverlay> createState() => _QROverlayState();
}

class _QROverlayState extends State<QROverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _dismissTimer = Timer(widget.displayDuration, () {
      _fadeController.reverse().then((_) {
        widget.onDismiss?.call();
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdQRCodeWidget(
                url: widget.url,
                size: 120,
                label: widget.callToAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
