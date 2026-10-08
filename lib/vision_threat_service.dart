import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'evidence_storage_service.dart';

class ThreatDetection {
  final String label;
  final double confidence;
  final List<double> boundingBox; // [x, y, w, h] normalized
  final bool isWeapon;
  final bool isSuspiciousFollower;

  ThreatDetection({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.isWeapon,
    required this.isSuspiciousFollower,
  });
}

class VisionThreatService {
  static final VisionThreatService _instance = VisionThreatService._internal();
  factory VisionThreatService() => _instance;
  VisionThreatService._internal();

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isProcessingFrame = false;

  int _consecutivePersonDetections = 0;
  DateTime? _firstPersonDetectedTime;

  final StreamController<List<ThreatDetection>> _detectionStreamController =
  StreamController<List<ThreatDetection>>.broadcast();
  Stream<List<ThreatDetection>> get detectionStream => _detectionStreamController.stream;

  static const int inputSize = 640;

  Future<void> init() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/yolov8n_threat.tflite');
      final labelData = await rootBundle.loadString('assets/models/coco_labels.txt');
      _labels = labelData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      print('VisionThreatService model init error: $e');
    }
  }

  void processCameraImage(CameraImage image) async {
    if (_isProcessingFrame || _interpreter == null) return;
    _isProcessingFrame = true;

    try {
      final rgbImage = _convertYUV420ToImage(image);
      final resizedImage = img.copyResize(rgbImage, width: inputSize, height: inputSize);

      final inputBytes = Float32List(1 * inputSize * inputSize * 3);
      int pixelIndex = 0;

      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = resizedImage.getPixel(x, y);
          inputBytes[pixelIndex++] = pixel.r / 255.0;
          inputBytes[pixelIndex++] = pixel.g / 255.0;
          inputBytes[pixelIndex++] = pixel.b / 255.0;
        }
      }

      final output = List.filled(1 * 84 * 8400, 0.0).reshape([1, 84, 8400]);
      _interpreter!.run(inputBytes.buffer.asFloat32List(), output);

      final List<ThreatDetection> detections = _parseYoloOutput(output[0]);

      bool hasCriticalThreat = false;
      for (var d in detections) {
        if (d.isWeapon || d.isSuspiciousFollower) {
          hasCriticalThreat = true;
          break;
        }
      }

      // INSTANTLY SAVE FRAME AS EVIDENCE IN LOCAL DEVICE STORAGE
      if (hasCriticalThreat) {
        final jpegBytes = Uint8List.fromList(img.encodeJpg(rgbImage, quality: 85));
        await EvidenceStorageService().saveEvidenceFrame(
          imageBytes: jpegBytes,
          threatType: detections.firstWhere((d) => d.isWeapon || d.isSuspiciousFollower).label,
          confidence: detections.map((d) => d.confidence).reduce(max),
          metadataNotes: 'Threat detected by Vision AI pipeline',
        );
      }

      _detectionStreamController.add(detections);
    } catch (e) {
      print('Vision frame error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  List<ThreatDetection> _parseYoloOutput(List<dynamic> rawOutput) {
    final List<ThreatDetection> results = [];
    bool personInCurrentFrame = false;

    for (int col = 0; col < 8400; col += 4) {
      double maxClassScore = 0;
      int bestClassIdx = -1;

      for (int c = 4; c < 84; c++) {
        final score = rawOutput[c][col] as double;
        if (score > maxClassScore) {
          maxClassScore = score;
          bestClassIdx = c - 4;
        }
      }

      if (maxClassScore < 0.45) continue;

      final className = bestClassIdx < _labels.length ? _labels[bestClassIdx].toLowerCase() : '';
      final isKnife = className.contains('knife') || className.contains('dagger');
      final isGun = className.contains('gun') || className.contains('pistol') || className.contains('weapon');
      final isPerson = className == 'person';

      if (isPerson) personInCurrentFrame = true;

      if (isKnife || isGun) {
        final cx = rawOutput[0][col] as double;
        final cy = rawOutput[1][col] as double;
        final w = rawOutput[2][col] as double;
        final h = rawOutput[3][col] as double;

        results.add(ThreatDetection(
          label: isKnife ? 'Dangerous Weapon: Knife' : 'Dangerous Weapon: Firearm',
          confidence: maxClassScore,
          boundingBox: [
            (cx - w / 2) / inputSize,
            (cy - h / 2) / inputSize,
            w / inputSize,
            h / inputSize,
          ],
          isWeapon: true,
          isSuspiciousFollower: false,
        ));
      }
    }

    // Follower persistence detection (>5 seconds presence)
    final now = DateTime.now();
    if (personInCurrentFrame) {
      _consecutivePersonDetections++;
      _firstPersonDetectedTime ??= now;

      final durationSeconds = now.difference(_firstPersonDetectedTime!).inSeconds;
      if (durationSeconds >= 5 && _consecutivePersonDetections > 10) {
        results.add(ThreatDetection(
          label: 'Suspicious Follower Detected (${durationSeconds}s proximity)',
          confidence: 0.88,
          boundingBox: [0.15, 0.15, 0.70, 0.70],
          isWeapon: false,
          isSuspiciousFollower: true,
        ));
      }
    } else {
      _consecutivePersonDetections = max(0, _consecutivePersonDetections - 1);
      if (_consecutivePersonDetections == 0) {
        _firstPersonDetectedTime = null;
      }
    }

    return results;
  }

  img.Image _convertYUV420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final imgImage = img.Image(width: width, height: height);

    final planeY = image.planes[0];
    final planeU = image.planes[1];
    final planeV = image.planes[2];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = planeU.bytesPerRow * (y ~/ 2) + (x ~/ 2) * (planeU.bytesPerPixel ?? 1);
        final yIndex = y * planeY.bytesPerRow + x;

        final yp = planeY.bytes[yIndex];
        final up = planeU.bytes[uvIndex];
        final vp = planeV.bytes[uvIndex];

        int r = (yp + (1.370705 * (vp - 128))).round().clamp(0, 255);
        int g = (yp - (0.337633 * (up - 128)) - (0.698001 * (vp - 128))).round().clamp(0, 255);
        int b = (yp + (1.732446 * (up - 128))).round().clamp(0, 255);

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return imgImage;
  }

  void dispose() {
    _interpreter?.close();
    _detectionStreamController.close();
  }
}