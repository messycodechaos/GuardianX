import 'dart:async';
import 'package:flutter/material.dart';
import 'sos_escalation_service.dart';

class SosConfirmationDialog extends StatefulWidget {
  final String threatReason;
  final List<String> emergencyNumbers;
  final VoidCallback onSafeConfirmed;

  const SosConfirmationDialog({
    super.key,
    required this.threatReason,
    required this.emergencyNumbers,
    required this.onSafeConfirmed,
  });

  static Future<void> show(
      BuildContext context, {
        required String threatReason,
        required List<String> emergencyNumbers,
        required VoidCallback onSafeConfirmed,
      }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SosConfirmationDialog(
        threatReason: threatReason,
        emergencyNumbers: emergencyNumbers,
        onSafeConfirmed: onSafeConfirmed,
      ),
    );
  }

  @override
  State<SosConfirmationDialog> createState() => _SosConfirmationDialogState();
}

class _SosConfirmationDialogState extends State<SosConfirmationDialog>
    with SingleTickerProviderStateMixin {
  int _secondsLeft = 10;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        _onCountdownExpired();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _onCountdownExpired() {
    Navigator.of(context).pop();
    SosEscalationService().triggerEmergencySOS(
      threatReason: widget.threatReason,
      emergencyPhoneNumbers: widget.emergencyNumbers,
      soundSiren: true,
    );
  }

  void _onUserSafe() {
    _timer?.cancel();
    Navigator.of(context).pop();
    widget.onSafeConfirmed();
  }

  void _onTriggerNow() {
    _timer?.cancel();
    Navigator.of(context).pop();
    SosEscalationService().triggerEmergencySOS(
      threatReason: widget.threatReason,
      emergencyPhoneNumbers: widget.emergencyNumbers,
      soundSiren: true,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.redAccent.withOpacity(0.5 + (_pulseController.value * 0.5)),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4 * _pulseController.value),
                    blurRadius: 30,
                    spreadRadius: 8,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 54, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  const Text(
                    'THREAT DETECTED!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.threatReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CircularProgressIndicator(
                          value: _secondsLeft / 10.0,
                          strokeWidth: 8,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
                        ),
                      ),
                      Text(
                        '$_secondsLeft',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Panic detected in your voice/video.\nAre you fine? SOS triggers upon zero.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white30),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _onUserSafe,
                          child: const Text("I'm Safe", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _onTriggerNow,
                          child: const Text('SOS NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}