import 'package:flutter/material.dart';
import 'ai_controller.dart';
import 'fake_call_screen.dart';
import 'app_theme.dart';

class AIScreen extends StatefulWidget {
  const AIScreen({super.key});
  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final ai = AIController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("AI Defense Layer"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.crimson,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "AUTONOMOUS THREAT SENSING",
                style: TextStyle(
                  color: AppTheme.crimson,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. ACOUSTIC THREAT DETECTION
          _aiSwitch(
            "Safety Ear (Voice Monitor)",
            "Automatically triggers SOS if it hears screams or glass breaking.",
            ai.isVoiceMonitorActive,
                (v) async {
              if (v) {
                bool success = await ai.startAcousticMonitor((reason, db) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(child: Text("🚨 $reason (${db.toStringAsFixed(1)} dB)")),
                        ],
                      ),
                      backgroundColor: Colors.redAccent,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                });

                setState(() => ai.isVoiceMonitorActive = success);

                if (!mounted) return;
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("🎧 Safety Ear listening! (Clap loudly or tap Test Trigger to verify)"),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                      action: SnackBarAction(
                        label: "TEST NOW",
                        textColor: Colors.white,
                        onPressed: () {
                          ai.testTriggerAcousticAlert((reason, db) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("🚨 $reason (${db.toStringAsFixed(1)} dB)"),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Microphone Permission Required"),
                      content: const Text("Safety Ear needs microphone access to detect high-decibel screams or glass shattering. Please grant microphone permission in Settings."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
                      ],
                    ),
                  );
                }
              } else {
                await ai.stopAcousticMonitor();
                setState(() => ai.isVoiceMonitorActive = false);
              }
            },
          ),

          // 2. VISUAL GUARD
          _aiSwitch(
            "Safety Eye (Visual Guard)",
            "AI analyzes camera frames for weapons or suspicious followers.",
            ai.isVisualGuardActive,
                (v) async {
              if (v) {
                bool success = await ai.startVisualGuard();
                setState(() => ai.isVisualGuardActive = success);
                if (!mounted) return;
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("👁️ Safety Eye Armed: ${ai.visualGuardStatus}"),
                      backgroundColor: Colors.blueAccent,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Camera Permission Required"),
                      content: const Text("Visual Guard requires camera access to scan for suspicious followers or threats. Please grant camera permission."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
                      ],
                    ),
                  );
                }
              } else {
                ai.stopVisualGuard();
                setState(() => ai.isVisualGuardActive = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Safety Eye disarmed"), duration: Duration(seconds: 2)),
                );
              }
            },
          ),

          // 3. SMART RADAR
          _aiSwitch(
            "Smart Safety Radar",
            "Notifies you if you enter high-risk areas based on historical data.",
            ai.isSmartRadarActive,
                (v) async {
              if (v) {
                setState(() => ai.isSmartRadarActive = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("📡 Querying GPS location and risk zones..."), duration: Duration(seconds: 1)),
                );
                final res = await ai.getLiveSafetyScore();
                if (!mounted) return;
                final double score = res['score'] ?? 85.0;
                final String status = res['status'] ?? 'Safe';

                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Row(
                      children: [
                        Icon(Icons.radar, color: score < 50 ? Colors.orange : Colors.green),
                        const SizedBox(width: 8),
                        const Text("Radar Diagnostics"),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Safety Score: ${score.toStringAsFixed(0)} / 100", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 8),
                        Text("Condition: $status"),
                        const SizedBox(height: 4),
                        if (res['lat'] != 0.0)
                          Text("GPS: ${res['lat'].toStringAsFixed(4)}, ${res['lng'].toStringAsFixed(4)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Acknowledge")),
                    ],
                  ),
                );
              } else {
                setState(() => ai.isSmartRadarActive = false);
              }
            },
          ),

          const SizedBox(height: 24),
          const Divider(color: AppTheme.cardBorder),
          const SizedBox(height: 24),

          // 4. GUARDIAN PHONE CALL
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.azure,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "DE-ESCALATION & DETERRENCE",
                style: TextStyle(
                  color: AppTheme.azure,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            color: AppTheme.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.cardBorder),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.azure.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_in_talk, color: AppTheme.azure),
              ),
              title: const Text(
                "Trigger Fake Guardian Call",
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: const Text(
                "Starts a loud tactical AI voice dialogue to project remote security presence.",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textMuted),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const FakeCallScreen())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiSwitch(String t, String s, bool val, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: val ? AppTheme.crimson.withOpacity(0.4) : AppTheme.cardBorder,
          width: 1.2,
        ),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(
          t,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            s,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
          ),
        ),
        value: val,
        onChanged: onChanged,
        activeColor: AppTheme.crimson,
        activeTrackColor: AppTheme.crimson.withOpacity(0.3),
      ),
    );
  }
}