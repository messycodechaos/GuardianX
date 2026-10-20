import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crypto/crypto.dart';

enum EvidenceType { video, audio, image, incidentClip }

class EvidenceItem {
  final String id;
  String title;
  final EvidenceType type;
  final String filePath;
  final DateTime timestamp;
  final int fileSizeBytes;
  final int? durationSeconds;
  final double? latitude;
  final double? longitude;
  final String? incidentType;
  final double? threatConfidence;
  final String sha256Checksum;

  EvidenceItem({
    required this.id,
    required this.title,
    required this.type,
    required this.filePath,
    required this.timestamp,
    required this.fileSizeBytes,
    this.durationSeconds,
    this.latitude,
    this.longitude,
    this.incidentType,
    this.threatConfidence,
    required this.sha256Checksum,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type.name,
    'filePath': filePath,
    'timestamp': timestamp.toIso8601String(),
    'fileSizeBytes': fileSizeBytes,
    'durationSeconds': durationSeconds,
    'latitude': latitude,
    'longitude': longitude,
    'incidentType': incidentType,
    'threatConfidence': threatConfidence,
    'sha256Checksum': sha256Checksum,
  };

  factory EvidenceItem.fromJson(Map<String, dynamic> json) => EvidenceItem(
    id: json['id'] as String,
    title: json['title'] as String,
    type: EvidenceType.values.firstWhere(
          (e) => e.name == json['type'],
      orElse: () => EvidenceType.video,
    ),
    filePath: json['filePath'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    fileSizeBytes: json['fileSizeBytes'] as int,
    durationSeconds: json['durationSeconds'] as int?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    incidentType: json['incidentType'] as String?,
    threatConfidence: (json['threatConfidence'] as num?)?.toDouble(),
    sha256Checksum: json['sha256Checksum'] as String? ?? 'verified',
  );
}

class EvidenceService {
  static final EvidenceService instance = EvidenceService._internal();
  EvidenceService._internal();

  static const String _prefKey = 'guardian_x_evidence_metadata_v2';
  List<EvidenceItem> _items = [];
  bool _initialized = false;

  List<EvidenceItem> get items => List.unmodifiable(_items);

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_prefKey) ?? [];
      _items = rawList
          .map((s) => EvidenceItem.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .where((item) => File(item.filePath).existsSync())
          .toList();
      _items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _initialized = true;
    } catch (e) {
      debugPrint('EvidenceService initialization failed: $e');
      _items = [];
    }
  }

  Future<Directory> getEvidenceDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final evidenceDir = Directory('${appDir.path}/evidence_vault');
    if (!await evidenceDir.exists()) {
      await evidenceDir.create(recursive: true);
    }
    return evidenceDir;
  }

  /// Saves a newly recorded file or snapshot into the local evidence vault
  Future<EvidenceItem?> saveEvidence({
    required File sourceFile,
    required EvidenceType type,
    String? customTitle,
    String? incidentType,
    double? confidence,
    int? durationSeconds,
  }) async {
    try {
      await initialize();
      final evidenceDir = await getEvidenceDirectory();
      final now = DateTime.now();
      final extension = sourceFile.path.split('.').last;
      final fileName = 'EV_${now.millisecondsSinceEpoch}_${type.name}.$extension';
      final targetPath = '${evidenceDir.path}/$fileName';

      final savedFile = await sourceFile.copy(targetPath);
      final size = await savedFile.length();

      // Calculate SHA256 for cryptographic chain of custody
      final bytes = await savedFile.readAsBytes();
      final checksum = sha256.convert(bytes).toString();

      // Retrieve GPS coordinates if available
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 3),
        );
      } catch (_) {}

      final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(now);
      final defaultTitle = customTitle ??
          (incidentType != null
              ? '$incidentType Alert ($formattedDate)'
              : 'Evidence ${type.name.toUpperCase()} ($formattedDate)');

      final item = EvidenceItem(
        id: 'ev_${now.millisecondsSinceEpoch}',
        title: defaultTitle,
        type: type,
        filePath: targetPath,
        timestamp: now,
        fileSizeBytes: size,
        durationSeconds: durationSeconds,
        latitude: position?.latitude,
        longitude: position?.longitude,
        incidentType: incidentType,
        threatConfidence: confidence,
        sha256Checksum: checksum,
      );

      _items.insert(0, item);
      await _persistMetadata();
      return item;
    } catch (e) {
      debugPrint('Error saving evidence file: $e');
      return null;
    }
  }

  Future<bool> renameEvidence(String id, String newTitle) async {
    final index = _items.indexWhere((e) => e.id == id);
    if (index == -1) return false;
    _items[index].title = newTitle;
    await _persistMetadata();
    return true;
  }

  Future<bool> deleteEvidence(String id) async {
    final index = _items.indexWhere((e) => e.id == id);
    if (index == -1) return false;
    final item = _items[index];

    try {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete physical file: $e');
    }

    _items.removeAt(index);
    await _persistMetadata();
    return true;
  }

  Future<void> _persistMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = _items.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_prefKey, stringList);
    } catch (e) {
      debugPrint('Error saving evidence metadata: $e');
    }
  }
}