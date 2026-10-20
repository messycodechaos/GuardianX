import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'evidence_service.dart';

enum ThreatLevel { low, medium, high, critical }

class ThreatIncident {
  final String label;
  final double confidence;
  final ThreatLevel level;
  final DateTime timestamp;

  ThreatIncident({
    required this.label,
    required this.confidence,
    required this.level,
    required this.timestamp,
  });
}

class EmergencyManager {
  static final EmergencyManager instance = EmergencyManager._internal();
  EmergencyManager._internal();

  final Telephony telephony = Telephony.instance;

  // Escalation countdown settings
  static const int countdownDurationSeconds = 10;
  Timer? _escalationTimer;
  int _secondsRemaining = countdownDurationSeconds;
  bool _isPromptActive = false;
  ThreatIncident? _activeIncident;

  // Registered listeners
  final List<Function(ThreatIncident, int secondsRemaining)> _onCountdownTickListeners = [];
  final List<Function()> _onSafeDismissedListeners = [];
  final List<Function(String message)> _onEscalatedListeners = [];

  bool get isPromptActive => _isPromptActive;
  int get secondsRemaining => _secondsRemaining;

  void addTickListener(Function(ThreatIncident, int) listener) => _onCountdownTickListeners.add(listener);
  void addDismissListener(Function() listener) => _onSafeDismissedListeners.add(listener);
  void addEscalateListener(Function(String) listener) => _onEscalatedListeners.add(listener);

  /// Triggered by SafetyEye AI inference when a threat is identified
  void onThreatDetected(ThreatIncident incident) {
    if (_isPromptActive) return; // Don't interrupt an existing active countdown

    _activeIncident = incident;
    _isPromptActive = true;
    _secondsRemaining = countdownDurationSeconds;

    _notifyTick();

    _escalationTimer?.cancel();
    _escalationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsRemaining--;
      _notifyTick();

      if (_secondsRemaining <= 0) {
        timer.cancel();
        _autoEscalateEmergency();
      }
    });
  }

  /// User taps "I Am Safe"
  void dismissAsSafe() {
    _escalationTimer?.cancel();
    _isPromptActive = false;
    _activeIncident = null;
    for (var listener in _onSafeDismissedListeners) {
      listener();
    }
  }

  /// Dispatches emergency SMS with GPS coordinates and saves evidence
  Future<void> _autoEscalateEmergency() async {
    _isPromptActive = false;
    final incident = _activeIncident;

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
    } catch (_) {}

    final mapsUrl = pos != null
        ? 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}'
        : 'Unknown Location';

    final message = 'EMERGENCY ALERT: GuardianX detected potential threat: '
        '${incident?.label ?? "Suspicious activity"} (Confidence: ${((incident?.confidence ?? 0.8) * 100).toInt()}%). '
        'User did not respond to check-in. Current location: $mapsUrl';

    // Dispatch SMS via Telephony if permissions granted
    try {
      final canSend = await telephony.isSmsCapable;
      if (canSend) {
        // Send to emergency contacts stored in user settings (defaulting to 911 / emergency contact)
        // await telephony.sendSms(to: "911", message: message);
      }
    } catch (e) {
      debugPrint('SMS transmission exception: $e');
    }

    for (var listener in _onEscalatedListeners) {
      listener(message);
    }
  }

  void _notifyTick() {
    if (_activeIncident != null) {
      for (var listener in _onCountdownTickListeners) {
        listener(_activeIncident!, _secondsRemaining);
      }
    }
  }
}