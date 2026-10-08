import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'audio_sensing_service.dart';
import 'vision_threat_service.dart';
import 'evidence_storage_service.dart';
import 'sos_escalation_service.dart';
import 'sos_confirmation_dialog.dart';

class GuardianSensingScreen extends StatefulWidget {
  final List<String> emergencyContacts;

  const GuardianSensingScreen({
    super.key,
    this.emergencyContacts = const ['+18005550199'],
  });

  @override
  State<GuardianSensingScreen> createState() => _GuardianSensingScreenState();
}

class _GuardianSensingScreenState extends State<GuardianSensingScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;
  bool _isFlashOn = false;
  double _sensitivity = 0.55;

  final AudioSensingService _audioService = AudioSensingService();
  final VisionThreatService _visionService = VisionThreatService();

  bool _isSosDialogOpen = false;
  AudioThreatResult? _latestAudio;
  List<ThreatDetection> _latestDetections = [];
  late List<String> _currentContacts;

  @override
  void initState() {
    super.initState();
    _currentContacts = List.from(widget.emergencyContacts);
    _initServices();
  }

  Future<void> _initServices() async {
    // 1. Initialize AI Models
    await _audioService.init();
    await _visionService.init();

    // 2. Initialize Camera
    _availableCameras = await availableCameras();
    if (_availableCameras.isNotEmpty) {
      await _startCamera(_selectedCameraIndex);
    }

    // 3. Start Audio Sensing with user sensitivity
    await _audioService.startContinuousSensing(sensitivityThreshold: _sensitivity);

    // 4. Listen to Audio Threat Stream
    _audioService.threatStream.listen((audio) {
      if (!mounted) return;
      setState(() => _latestAudio = audio);

      if (audio.isPanic && !_isSosDialogOpen) {
        _handleThreatTriggered(
          'Vocal Strain / Panic Detected: ${audio.threatClass} (${audio.decibels.toStringAsFixed(1)} dB)',
        );
      }
    });

    // 5. Listen to Vision Threat Stream
    _visionService.detectionStream.listen((detections) {
      if (!mounted) return;
      setState(() => _latestDetections = detections);

      for (var d in detections) {
        if ((d.isWeapon || d.isSuspiciousFollower) && !_isSosDialogOpen) {
          _handleThreatTriggered('${d.label} (Confidence: ${(d.confidence * 100).toStringAsFixed(0)}%)');
          break;
        }
      }
    });

    if (mounted) setState(() {});
  }

  Future<void> _startCamera(int index) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      _availableCameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      _cameraController!.startImageStream((image) {
        _visionService.processCameraImage(image);
      });
      if (mounted) setState(() {});
    } catch (e) {
      print('Camera initialization error: $e');
    }
  }

  void _flipCamera() async {
    if (_availableCameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
    await _startCamera(_selectedCameraIndex);
  }

  void _toggleFlash() async {
    if (_cameraController == null) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  void _handleThreatTriggered(String reason) {
    setState(() => _isSosDialogOpen = true);
    SosConfirmationDialog.show(
      context,
      threatReason: reason,
      emergencyNumbers: _currentContacts,
      onSafeConfirmed: () {
        setState(() => _isSosDialogOpen = false);
      },
    ).then((_) {
      if (mounted) setState(() => _isSosDialogOpen = false);
    });
  }

  void _openSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('GuardianX Sentinel Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Text('Audio Threat Sensitivity: ${(_sensitivity * 100).toInt()}%', style: const TextStyle(color: Colors.white70)),
                  Slider(
                    value: _sensitivity,
                    min: 0.35,
                    max: 0.85,
                    divisions: 10,
                    activeColor: Colors.redAccent,
                    onChanged: (val) {
                      setModalState(() => _sensitivity = val);
                      setState(() => _sensitivity = val);
                      _audioService.stop();
                      _audioService.startContinuousSensing(sensitivityThreshold: val);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Registered Emergency Contacts:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                  ..._currentContacts.map((c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('• $c', style: const TextStyle(color: Colors.tealAccent, fontFamily: 'monospace')),
                  )),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openEvidenceVault() async {
    final evidence = await EvidenceStorageService().getAllEvidence();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12121C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          builder: (ctx, scroll) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  Text('Evidence Locker (${evidence.length} Frames)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: evidence.isEmpty
                        ? const Center(child: Text('No threat frames captured yet.', style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                      controller: scroll,
                      itemCount: evidence.length,
                      itemBuilder: (ctx, idx) {
                        final item = evidence[idx];
                        return Card(
                          color: const Color(0xFF1E1E2C),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: File(item.imagePath).existsSync()
                                  ? Image.file(File(item.imagePath), width: 50, height: 50, fit: BoxFit.cover)
                                  : const Icon(Icons.broken_image, color: Colors.red),
                            ),
                            title: Text(item.threatType, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text('${item.timestamp} | ${item.latitude.toStringAsFixed(3)}, ${item.longitude.toStringAsFixed(3)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            trailing: const Icon(Icons.lock, color: Colors.redAccent, size: 18),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioService.dispose();
    _visionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Preview
          CameraPreview(_cameraController!),

          // 2. Vision Bounding Box Overlay
          CustomPaint(
            painter: BoundingBoxPainter(_latestDetections),
          ),

          // 3. Top HUD: Audio Sensing & Decibels
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: _buildAudioHud(),
          ),

          // 4. Quick Controls: Camera Flip, Flash, Vault, Settings
          Positioned(
            right: 16,
            top: 120,
            child: Column(
              children: [
                _buildCircleButton(icon: Icons.flip_camera_ios, onTap: _flipCamera),
                const SizedBox(height: 10),
                _buildCircleButton(
                  icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                  color: _isFlashOn ? Colors.amber : Colors.white,
                  onTap: _toggleFlash,
                ),
                const SizedBox(height: 10),
                _buildCircleButton(icon: Icons.shield, onTap: _openEvidenceVault),
                const SizedBox(height: 10),
                _buildCircleButton(icon: Icons.tune, onTap: _openSettingsDialog),
              ],
            ),
          ),

          // 5. Bottom SOS Action Bar
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onTap, Color color = Colors.white}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildAudioHud() {
    final stress = _latestAudio?.stressScore ?? 0.0;
    final db = _latestAudio?.decibels ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stress > 65 ? Colors.redAccent : Colors.white24),
      ),
      child: Row(
        children: [
          Icon(
            Icons.mic,
            color: stress > 65 ? Colors.redAccent : Colors.greenAccent,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Acoustic Strain: ${stress.toStringAsFixed(0)}% | ${db.toStringAsFixed(0)} dB',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: (stress / 100).clamp(0.0, 1.0),
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(
                    stress > 65 ? Colors.redAccent : Colors.tealAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.sos, color: Colors.white, size: 28),
      label: const Text(
        'MANUAL EMERGENCY SOS',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      onPressed: () {
        _handleThreatTriggered('Manual User Distress SOS');
      },
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<ThreatDetection> detections;
  BoundingBoxPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    for (var d in detections) {
      final rect = Rect.fromLTWH(
        d.boundingBox[0] * size.width,
        d.boundingBox[1] * size.height,
        d.boundingBox[2] * size.width,
        d.boundingBox[3] * size.height,
      );

      final paint = Paint()
        ..color = (d.isWeapon || d.isSuspiciousFollower) ? Colors.redAccent : Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}