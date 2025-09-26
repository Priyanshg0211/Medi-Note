class RecordingSession {
  final String id;
  final String patientId;
  final String patientName;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? duration;
  final RecordingStatus status;
  final String? templateId;
  final int totalChunks;

  RecordingSession({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.userId,
    required this.startTime,
    this.endTime,
    this.duration,
    required this.status,
    this.templateId,
    this.totalChunks = 0,
  });

  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    return RecordingSession(
      id: json['id'],
      patientId: json['patientId'],
      patientName: json['patientName'],
      userId: json['userId'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      duration: json['duration'] != null ? Duration(seconds: json['duration']) : null,
      status: RecordingStatus.values.byName(json['status']),
      templateId: json['templateId'],
      totalChunks: json['totalChunks'] ?? 0,
    );
  }
}

enum RecordingStatus {
  recording,
  paused,
  completed,
  error,
}