import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AIController {
  static final AIController _instance = AIController._internal();
  factory AIController() => _instance;
  AIController._internal();

  bool isVoiceMonitorActive = false;
  bool isVisualGuardActive = false;
  bool isSmartRadarActive = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _acousticTimer;
  double currentDecibels = -60.0;
  String visualGuardStatus = "Standby";

  // Pretrained ML & Camera Elements
  CameraController? cameraController;
  ObjectDetector? _objectDetector;
  ImageLabeler? _imageLabeler;
  final FlutterTts _tts = FlutterTts();

  bool _isProcessingFrame = false;
  DateTime _lastFrameProcessedTime = DateTime.now();
  int _consecutiveFollowerFrames = 0;

  // Visual Threat Callback
  Function(String reason, double confidence)? onVisualThreatTriggered;

  // =========================================================================
  // 1. ACOUSTIC THREAT DETECTION (Safety Ear)
  // =========================================================================
  Future<bool> startAcousticMonitor(Function(String reason, double db) onThreatDetected) async {
    isVoiceMonitorActive = true;
    try {
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      if (!status.isGranted) {
        isVoiceMonitorActive = false;
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final tempAudioPath = '${tempDir.path}/ai_acoustic_monitor.m4a';

      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 22050),
        path: tempAudioPath,
      );

      _acousticTimer?.cancel();
      _acousticTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
        if (!isVoiceMonitorActive) {
          timer.cancel();
          try { await _audioRecorder.stop(); } catch (_) {}
          return;
        }

        try {
          final amp = await _audioRecorder.getAmplitude();
          currentDecibels = amp.current;

          // Responsive threshold: clapping, shouting, or loud sounds exceed -24 dBFS
          if (amp.current > -24.0) {
            _triggerThreatAlert(onThreatDetected, "Acoustic Threat / High Decibel Anomaly", amp.current);
          }
        } catch (e) {
          debugPrint("Acoustic monitor error: $e");
        }
      });

      return true;
    } catch (e) {
      debugPrint("Failed to start acoustic monitor: $e");
      isVoiceMonitorActive = false;
      return false;
    }
  }

  void _triggerThreatAlert(Function(String, double) onThreatDetected, String reason, double db) async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 300, 150, 300]);
      }
    } catch (_) {}
    onThreatDetected(reason, db);
  }

  void testTriggerAcousticAlert(Function(String, double) onThreatDetected) {
    _triggerThreatAlert(onThreatDetected, "TEST: Simulated Scream / Audio Anomaly", -12.5);
  }

  Future<void> stopAcousticMonitor() async {
    isVoiceMonitorActive = false;
    _acousticTimer?.cancel();
    try {
      if (await _audioRecorder.isRecording()) await _audioRecorder.stop();
    } catch (_) {}
  }

  // =========================================================================
  // 2. SMART SAFETY RADAR
  // =========================================================================
  Future<Map<String, dynamic>> getLiveSafetyScore() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {'score': _calculateTimeScore(), 'lat': 0.0, 'lng': 0.0, 'status': 'Device GPS is OFF (using time zone)'};
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );

      double score = _calculateTimeScore();
      return {
        'score': score,
        'lat': position.latitude,
        'lng': position.longitude,
        'status': score < 50 ? 'High-Risk Night Zone' : 'Daylight Low-Risk Safe Corridor',
      };
    } catch (e) {
      return {'score': _calculateTimeScore(), 'lat': 0.0, 'lng': 0.0, 'status': 'Standard Zone Patrol'};
    }
  }

  double _calculateTimeScore() {
    int hour = DateTime.now().hour;
    if (hour >= 22 || hour < 5) return 45.0; // High risk at night
    if (hour >= 18 || hour < 22) return 68.0; // Moderate dusk caution
    return 85.0; // Safe daylight
  }

  // =========================================================================
  // 3. VISUAL GUARD (Safety Eye with Pretrained ML Models)
  // =========================================================================
  Future<void> _initPretrainedModels() async {
    // 1. Pretrained Stream Object Detector for Person Tracking
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);

    // 2. Pretrained Image Labeler for Weapon Classification (COCO/ImageNet 80+ classes)
    final labelerOptions = ImageLabelerOptions(confidenceThreshold: 0.55);
    _imageLabeler = ImageLabeler(options: labelerOptions);

    try {
      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.5);
    } catch (_) {}
  }

  Future<bool> startVisualGuard({
    Function(String reason, double threatConfidence)? onThreat,
  }) async {
    onVisualThreatTriggered = onThreat;

    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
      if (!status.isGranted) {
        isVisualGuardActive = false;
        visualGuardStatus = "Camera permission denied";
        return false;
      }

      await _initPretrainedModels();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        visualGuardStatus = "No camera found on device";
        isVisualGuardActive = false;
        return false;
      }

      // Default to rear camera for follower tracking behind the user
      CameraDescription selectedCamera = cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await cameraController!.initialize();

      // Start continuous real-time image stream
      await cameraController!.startImageStream((CameraImage image) {
        _processFrame(image, selectedCamera);
      });

      isVisualGuardActive = true;
      _consecutiveFollowerFrames = 0;
      visualGuardStatus = "Active: Scanning for followers & weapons";
      return true;
    } catch (e) {
      debugPrint("Failed to start Safety Eye: $e");
      visualGuardStatus = "Error: $e";
      isVisualGuardActive = false;
      return false;
    }
  }

  void _processFrame(CameraImage image, CameraDescription camera) async {
    if (_isProcessingFrame || !isVisualGuardActive) return;

    final now = DateTime.now();
    // Throttle inference to 1 frame every 1000ms for smooth UI & battery saving
    if (now.difference(_lastFrameProcessedTime).inMilliseconds < 1000) return;

    _isProcessingFrame = true;
    _lastFrameProcessedTime = now;

    try {
      final inputImage = _convertCameraImageToInputImage(image, camera);
      if (inputImage == null) return;

      final detectedObjects = await _objectDetector!.processImage(inputImage);
      final labels = await _imageLabeler!.processImage(inputImage);

      // --- 1. WEAPON DETECTION CHECK ---
      final weaponKeywords = ['knife', 'gun', 'weapon', 'dagger', 'blade', 'scissors', 'bat'];
      for (final label in labels) {
        final textLower = label.label.toLowerCase();
        for (final kw in weaponKeywords) {
          if (textLower.contains(kw) && label.confidence > 0.55) {
            _triggerVisualAlert(
              "WEAPON DETECTED: ${label.label} (${(label.confidence * 100).toStringAsFixed(0)}%)",
              label.confidence,
            );
            return;
          }
        }
      }

      // --- 2. SUSPICIOUS FOLLOWER DETECTION ---
      bool personInFrame = detectedObjects.any((obj) =>
          obj.labels.any((l) => l.text.toLowerCase().contains("person"))
      ) || labels.any((l) => l.label.toLowerCase().contains("person") && l.confidence > 0.65);

      if (personInFrame) {
        _consecutiveFollowerFrames++;
        visualGuardStatus = "Tracking person behind you (${_consecutiveFollowerFrames}s)";

        // If person continues following for 4+ consecutive seconds
        if (_consecutiveFollowerFrames >= 4) {
          _triggerVisualAlert(
            "SUSPICIOUS FOLLOWER: Trailing for ${_consecutiveFollowerFrames} seconds",
            0.85,
          );
        }
      } else {
        if (_consecutiveFollowerFrames > 0) _consecutiveFollowerFrames--;
        if (_consecutiveFollowerFrames == 0) {
          visualGuardStatus = "Scanning: Path clear";
        }
      }
    } catch (e) {
      debugPrint("Frame ML analysis error: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _triggerVisualAlert(String reason, double confidence) async {
    visualGuardStatus = "⚠️ $reason";

    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 400, 150, 400, 150, 400]);
      }
      await _tts.speak("Warning. Safety Eye detected a potential threat.");
    } catch (_) {}

    onVisualThreatTriggered?.call(reason, confidence);
  }

  Future<void> stopVisualGuard() async {
    isVisualGuardActive = false;
    visualGuardStatus = "Standby";
    _consecutiveFollowerFrames = 0;

    try {
      if (cameraController != null && cameraController!.value.isStreamingImages) {
        await cameraController!.stopImageStream();
      }
      await cameraController?.dispose();
      cameraController = null;

      await _objectDetector?.close();
      await _imageLabeler?.close();
      _objectDetector = null;
      _imageLabeler = null;
    } catch (e) {
      debugPrint("Error stopping Safety Eye: $e");
    }
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image, CameraDescription camera) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}