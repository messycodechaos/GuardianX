import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

class SosEscalationService {
  static final SosEscalationService _instance = SosEscalationService._internal();
  factory SosEscalationService() => _instance;
  SosEscalationService._internal();

  final AudioPlayer _sirenPlayer = AudioPlayer();
  final Telephony _telephony = Telephony.instance;
  bool _isSirenActive = false;

  bool get isSirenActive => _isSirenActive;

  Future<void> triggerEmergencySOS({
    required String threatReason,
    required List<String> emergencyPhoneNumbers,
    bool soundSiren = true,
  }) async {
    if (soundSiren) {
      await startSiren();
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 4),
      );
    } catch (_) {}

    final mapsUrl = position != null
        ? 'https://maps.google.com/?q=${position.latitude},${position.longitude}'
        : 'Location unavailable';

    final message = '''
🚨 GUARDIANX EMERGENCY ALERT 🚨
Threat Detected: $threatReason
User did not respond to safety check!
Live Location: $mapsUrl
Time: ${DateTime.now().toLocal()}
Please check immediately or notify police!
''';

    for (String phone in emergencyPhoneNumbers) {
      try {
        await _telephony.sendSms(
          to: phone,
          message: message,
          isMultipart: true,
        );
      } catch (e) {
        print('SMS dispatch error for $phone: $e');
      }
    }

    if (emergencyPhoneNumbers.isNotEmpty) {
      final uri = Uri.parse('tel:${emergencyPhoneNumbers.first}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  Future<void> startSiren() async {
    if (_isSirenActive) return;
    try {
      _isSirenActive = true;
      await _sirenPlayer.setReleaseMode(ReleaseMode.loop);
      await _sirenPlayer.setVolume(1.0);
      await _sirenPlayer.play(AssetSource('audio/emergency_siren.mp3'));
    } catch (e) {
      print('Siren error: $e');
    }
  }

  Future<void> stopSiren() async {
    _isSirenActive = false;
    await _sirenPlayer.stop();
  }
}