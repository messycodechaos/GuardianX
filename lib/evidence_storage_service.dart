import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

class EvidenceRecord {
  final String id;
  final String imagePath;
  final String timestamp;
  final String threatType;
  final double confidence;
  final double latitude;
  final double longitude;
  final String sha256Hash;
  final String notes;

  EvidenceRecord({
    required this.id,
    required this.imagePath,
    required this.timestamp,
    required this.threatType,
    required this.confidence,
    required this.latitude,
    required this.longitude,
    required this.sha256Hash,
    required this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'timestamp': timestamp,
    'threatType': threatType,
    'confidence': confidence,
    'latitude': latitude,
    'longitude': longitude,
    'sha256Hash': sha256Hash,
    'notes': notes,
  };
}

class EvidenceStorageService {
  static final EvidenceStorageService _instance = EvidenceStorageService._internal();
  factory EvidenceStorageService() => _instance;
  EvidenceStorageService._internal();

  Future<Directory> _getEvidenceDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final evidenceDir = Directory('${appDir.path}/evidence_vault');
    if (!await evidenceDir.exists()) {
      await evidenceDir.create(recursive: true);
    }
    return evidenceDir;
  }

  Future<EvidenceRecord> saveEvidenceFrame({
    required Uint8List imageBytes,
    required String threatType,
    required double confidence,
    required String metadataNotes,
  }) async {
    final dir = await _getEvidenceDirectory();
    final now = DateTime.now();
    final recordId = 'EV_${now.millisecondsSinceEpoch}';

    final imageFile = File('${dir.path}/$recordId.jpg');
    await imageFile.writeAsBytes(imageBytes, flush: true);

    final hash = sha256.convert(imageBytes).toString();

    double lat = 0.0;
    double lng = 0.0;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    final record = EvidenceRecord(
      id: recordId,
      imagePath: imageFile.path,
      timestamp: now.toIso8601String(),
      threatType: threatType,
      confidence: confidence,
      latitude: lat,
      longitude: lng,
      sha256Hash: hash,
      notes: metadataNotes,
    );

    final metaFile = File('${dir.path}/$recordId.json');
    await metaFile.writeAsString(jsonEncode(record.toJson()), flush: true);

    return record;
  }

  Future<List<EvidenceRecord>> getAllEvidence() async {
    final dir = await _getEvidenceDirectory();
    final List<EvidenceRecord> list = [];
    final files = dir.listSync();

    for (var f in files) {
      if (f.path.endsWith('.json')) {
        try {
          final content = await File(f.path).readAsString();
          final map = jsonDecode(content);
          list.add(EvidenceRecord(
            id: map['id'],
            imagePath: map['imagePath'],
            timestamp: map['timestamp'],
            threatType: map['threatType'],
            confidence: (map['confidence'] as num).toDouble(),
            latitude: (map['latitude'] as num).toDouble(),
            longitude: (map['longitude'] as num).toDouble(),
            sha256Hash: map['sha256Hash'],
            notes: map['notes'],
          ));
        } catch (_) {}
      }
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }
}