import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class ChunkStoreEntry {
  final String sessionId;
  final int chunkNumber;
  final String filePath;
  final DateTime timestamp;

  ChunkStoreEntry({
    required this.sessionId,
    required this.chunkNumber,
    required this.filePath,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'chunkNumber': chunkNumber,
        'filePath': filePath,
        'timestamp': timestamp.toIso8601String(),
      };

  static ChunkStoreEntry fromJson(Map<String, dynamic> json) {
    return ChunkStoreEntry(
      sessionId: json['sessionId'] as String,
      chunkNumber: (json['chunkNumber'] as num).toInt(),
      filePath: json['filePath'] as String,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChunkStore {
  static const String _folderName = 'chunks';
  static const String _manifestName = 'manifest.json';

  Future<Directory> _ensureChunksDir() async {
    final dir = await getApplicationSupportDirectory();
    final chunksDir = Directory('${dir.path}/$_folderName');
    if (!await chunksDir.exists()) {
      await chunksDir.create(recursive: true);
    }
    return chunksDir;
  }

  Future<File> _manifestFile() async {
    final dir = await _ensureChunksDir();
    return File('${dir.path}/$_manifestName');
  }

  Future<List<ChunkStoreEntry>> loadAll() async {
    try {
      final file = await _manifestFile();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.trim().isEmpty) return [];
      final List<dynamic> list = json.decode(text);
      return list
          .map((e) => ChunkStoreEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<ChunkStoreEntry> entries) async {
    final file = await _manifestFile();
    await file.writeAsString(json.encode(entries.map((e) => e.toJson()).toList()));
  }

  Future<ChunkStoreEntry> writeChunk(
      {required String sessionId,
      required int chunkNumber,
      required Uint8List bytes}) async {
    final dir = await _ensureChunksDir();
    final fileName = '${sessionId}_$chunkNumber.wav';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    final entry = ChunkStoreEntry(
      sessionId: sessionId,
      chunkNumber: chunkNumber,
      filePath: file.path,
      timestamp: DateTime.now(),
    );
    final entries = await loadAll();
    entries.add(entry);
    await _saveAll(entries);
    return entry;
  }

  Future<Uint8List?> readChunkBytes(ChunkStoreEntry entry) async {
    try {
      final file = File(entry.filePath);
      if (!await file.exists()) return null;
      final data = await file.readAsBytes();
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(ChunkStoreEntry entry) async {
    final entries = await loadAll();
    entries.removeWhere((e) =>
        e.sessionId == entry.sessionId && e.chunkNumber == entry.chunkNumber);
    await _saveAll(entries);
    try {
      final f = File(entry.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }
}


