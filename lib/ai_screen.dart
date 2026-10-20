import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'ai_controller.dart';
import 'services/emergency_manager.dart';

class AIScreen extends StatefulWidget {
  const AIScreen({Key? key}) : super(key: key);

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final AIController _controller = AIController();
  ThreatIncident? _activeIncident;
  int _secondsRemaining = 10;
  bool _showingAlertModal = false;

  @override
  void initState() {
    super.initState();
    _controller.startSafetyEye();

    // Listen for threat triggers from EmergencyManager
    EmergencyManager.instance.addTickListener((incident, seconds) {
      if (mounted) {
        setState(() {
          _activeIncident = incident;
          _secondsRemaining = seconds;
          _showingAlertModal = true;
        });
      }
    });

    EmergencyManager.instance.addDismissListener(() {
      if (mounted) {
        setState(() {
          _showingAlertModal = false;
          _activeIncident = null;
        });
      }
    });

    EmergencyManager.instance.addEscalateListener((msg) {
      if (mounted) {
        setState(() => _showingAlertModal = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(msg, maxLines: 3),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Viewfinder
          if (_controller.isInitialized && _controller.cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_controller.cameraController!),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            ),

          // 2. HUD Top Bar
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'SAFETY EYE AI',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    _controller.statusMessage,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // 3. Auto-Escalation Check-In Modal
          if (_showingAlertModal && _activeIncident != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 4,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _activeIncident!.label,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_secondsRemaining}s',
                            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Are you safe? If you do not respond, GuardianX will automatically dispatch an emergency SOS alert with your live location.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => EmergencyManager.instance.dismissAsSafe(),
                            child: const Text('I AM SAFE', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              // Immediate trigger
                              EmergencyManager.instance.onThreatDetected(_activeIncident!);
                            },
                            child: const Text('CALL HELP', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}