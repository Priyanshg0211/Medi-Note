import 'dart:typed_data';

class AudioChunk {
  final String sessionId;
  final int chunkNumber;
  final Uint8List audioData;
  final DateTime timestamp;
  final bool isUploaded;
  final String? publicUrl;

  AudioChunk({
    required this.sessionId,
    required this.chunkNumber,
    required this.audioData,
    required this.timestamp,
    this.isUploaded = false,
    this.publicUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'chunkNumber': chunkNumber,
      'timestamp': timestamp.toIso8601String(),
      'isUploaded': isUploaded,
      'publicUrl': publicUrl,
    };
  }
}

