import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'record_service.dart';
import 'app_theme.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _isTestingRecord = false;
  int _secondsLeft = 5;
  Timer? _countdownTimer;

  Future<List<FileSystemEntity>> _getAllRecords() async {
    Directory? baseDir = await getExternalStorageDirectory();
    baseDir ??= await getApplicationDocumentsDirectory();
    List<FileSystemEntity> allFiles = [];

    // Check Audio Folder
    Directory audioDir = Directory("${baseDir.path}/GuardianX/Audio");
    if (audioDir.existsSync()) {
      allFiles.addAll(audioDir.listSync().where((f) => f is File && !f.path.endsWith('.tmp')));
    }

    // Check Video Folder
    Directory videoDir = Directory("${baseDir.path}/GuardianX/Video");
    if (videoDir.existsSync()) {
      allFiles.addAll(videoDir.listSync().where((f) => f is File && !f.path.endsWith('.tmp')));
    }

    // Sort by date (Newest first)
    allFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return allFiles;
  }

  void _runQuickTestRecord() async {
    setState(() {
      _isTestingRecord = true;
      _secondsLeft = 5;
    });

    try {
      await RecordService().startLocalRecord();
    } catch (e) {
      if (mounted) {
        setState(() => _isTestingRecord = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Recording error: $e")),
        );
      }
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        try {
          await RecordService().stopLocalRecord();
        } catch (_) {}
        setState(() => _isTestingRecord = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Test Evidence Saved to Vault!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Evidence Vault"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textPrimary),
            onPressed: () => setState(() {}),
          )
        ],
      ),
      body: Column(
        children: [
          // Quick Test Evidence Banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Test Evidence Vault",
                        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isTestingRecord
                            ? "Recording test audio evidence... ($_secondsLeft s)"
                            : "Record a 5-second audio clip to verify file storage in the vault.",
                        style: TextStyle(
                          color: _isTestingRecord ? AppTheme.crimson : AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTestingRecord ? AppTheme.crimson : AppTheme.azure,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isTestingRecord ? null : _runQuickTestRecord,
                  icon: Icon(_isTestingRecord ? Icons.fiber_manual_record : Icons.mic, size: 18),
                  label: Text(_isTestingRecord ? "$_secondsLeft s" : "Test Now"),
                ),
              ],
            ),
          ),

          // File List
          Expanded(
            child: FutureBuilder<List<FileSystemEntity>>(
              future: _getAllRecords(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.crimson));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 64, color: AppTheme.textMuted.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        const Text("No Evidence Files Yet", style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            "Recordings from SOS Level 3 or the Test button above will be stored securely here.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    FileSystemEntity file = snapshot.data![index];
                    String name = file.path.split('/').last;
                    bool isVideo = name.contains('VID_');
                    final stat = file.statSync();
                    final sizeKb = (stat.size / 1024).toStringAsFixed(1);
                    final modifiedStr = stat.modified.toString().substring(0, 19);

                    return Card(
                      color: AppTheme.card,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isVideo ? AppTheme.azure.withOpacity(0.15) : AppTheme.amber.withOpacity(0.15),
                          child: Icon(
                            isVideo ? Icons.videocam : Icons.mic,
                            color: isVideo ? AppTheme.azure : AppTheme.amber,
                          ),
                        ),
                        title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text("$sizeKb KB  •  $modifiedStr", style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted),
                          onPressed: () {
                            try {
                              file.deleteSync();
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("File deleted")),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Delete error: $e")),
                              );
                            }
                          },
                        ),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Row(
                                children: [
                                  Icon(isVideo ? Icons.videocam : Icons.mic, color: Colors.redAccent),
                                  const SizedBox(width: 8),
                                  const Text("Evidence Details"),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Filename: $name", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text("Size: $sizeKb KB"),
                                  const SizedBox(height: 4),
                                  Text("Recorded: $modifiedStr"),
                                  const SizedBox(height: 8),
                                  const Text("Storage Path:", style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(file.path, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}