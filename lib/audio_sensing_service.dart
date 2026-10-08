import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class AudioThreatResult {
  final bool isPanic;
  final String threatClass;
  final double confidence;
  final double decibels;
  final double pitchHz;
  final double stressScore;

  AudioThreatResult({
    required this.isPanic,
    required this.threatClass,
    required this.confidence,
    required this.decibels,
    required this.pitchHz,
    required this.stressScore,
  });
}

class AudioSensingService {
  static final AudioSensingService _instance = AudioSensingService._internal();
  factory AudioSensingService() => _instance;
  AudioSensingService._internal();

  Interpreter? _interpreter;
  List<String> _labels = [];
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  bool _isListening = false;

  final StreamController<AudioThreatResult> _threatStreamController =
  StreamController<AudioThreatResult>.broadcast();
  Stream<AudioThreatResult> get threatStream => _threatStreamController.stream;

  // YAMNet requires exactly 15,600 samples at 16,000 Hz (~0.975s)
  static const int sampleRate = 16000;
  static const int requiredSamples = 15600;
  final List<double> _audioBuffer = [];

  static const Set<String> panicClasses = {
    'Screaming',
    'Scream',
    'Crying, sobbing',
    'Shout',
    'Yell',
    'Groan',
    'Wail, moan',
    'Gunshot, gunfire',
  };

  Future<void> init() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
      final labelData = await rootBundle.loadString('assets/models/yamnet_labels.txt');
      _labels = labelData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      print('AudioSensingService init error: $e');
    }
  }

  Future<void> startContinuousSensing({double sensitivityThreshold = 0.55}) async {
    if (_isListening) return;

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) return;

    _isListening = true;

    // Stream raw 16kHz mono PCM 16-bit
    final recordStream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    _streamSub = recordStream.listen((chunk) {
      _processAudioChunk(chunk, sensitivityThreshold);
    });
  }

  void _processAudioChunk(Uint8List chunk, double sensitivityThreshold) {
    final byteData = ByteData.sublistView(chunk);
    for (int i = 0; i < byteData.lengthInBytes - 1; i += 2) {
      final sample = byteData.getInt16(i, Endian.little);
      _audioBuffer.add(sample / 32768.0);
    }

    if (_audioBuffer.length >= requiredSamples) {
      final inputWindow = _audioBuffer.sublist(0, requiredSamples);
      _audioBuffer.removeRange(0, 8000); // 50% sliding step

      _runInference(inputWindow, sensitivityThreshold);
    }
  }

  void _runInference(List<double> samples, double threshold) {
    if (_interpreter == null) return;

    try {
      double sumSquares = 0;
      int zeroCrossings = 0;
      for (int i = 0; i < samples.length; i++) {
        sumSquares += samples[i] * samples[i];
        if (i > 0 && ((samples[i] >= 0 && samples[i - 1] < 0) || (samples[i] < 0 && samples[i - 1] >= 0))) {
          zeroCrossings++;
        }
      }

      final rms = sqrt(sumSquares / samples.length);
      final decibels = (20 * log(max(rms, 0.00001)) / ln10) + 90;
      final approxPitch = (zeroCrossings * sampleRate) / (2 * samples.length);

      final stressScore = min(1.0, max(0.0, ((decibels - 60) / 40.0) * 0.6 + ((approxPitch - 250) / 400.0) * 0.4));

      final input = Float32List.fromList(samples);
      final output = List.filled(521, 0.0).reshape([1, 521]);

      _interpreter!.run(input, output);

      final probabilities = output[0] as List<dynamic>;
      double maxScore = 0.0;
      int bestIdx = 0;

      for (int i = 0; i < probabilities.length; i++) {
        final score = probabilities[i] as double;
        if (score > maxScore) {
          maxScore = score;
          bestIdx = i;
        }
      }

      final topClass = bestIdx < _labels.length ? _labels[bestIdx] : 'Unknown';
      final isPanicClass = panicClasses.contains(topClass) && maxScore >= threshold;
      final isAcousticScream = decibels > 82.0 && approxPitch > 450.0 && stressScore > 0.70;
      final isThreat = isPanicClass || isAcousticScream;

      _threatStreamController.add(AudioThreatResult(
        isPanic: isThreat,
        threatClass: isPanicClass ? topClass : (isAcousticScream ? 'Acoustic Scream / High Strain' : topClass),
        confidence: max(maxScore, stressScore),
        decibels: decibels,
        pitchHz: approxPitch,
        stressScore: stressScore * 100,
      ));
    } catch (e) {
      print('YAMNet inference error: $e');
    }
  }

  Future<void> stop() async {
    await _streamSub?.cancel();
    await _audioRecorder.stop();
    _isListening = false;
    _audioBuffer.clear();
  }

  void dispose() {
    stop();
    _interpreter?.close();
    _threatStreamController.close();
  }
}