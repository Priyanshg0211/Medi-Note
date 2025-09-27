import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';
import '../services/chunk_store.dart';
import '../services/firebase_service.dart';
import '../services/connectivity_service.dart';

class RecordingProvider extends ChangeNotifier {
  final AudioService _audioService = AudioService();
  final ChunkStore _chunkStore = ChunkStore();
  final ConnectivityService _connectivityService = ConnectivityService();

  RecordingState _state = RecordingState.idle;
  String? _sessionId;
  String? _userId;
  String? _patientName;
  DateTime? _startTime;
  Duration _duration = Duration.zero;
  double _audioLevel = 0.0;
  int _lastUploadedChunkNumber = 0;
  String? _lastGcsPath;
  String? _lastPublicUrl;

  List<PendingChunk> _pendingChunks = [];
  bool _isOnline = true;
  bool _isInterrupted = false;

  RecordingState get state => _state;
  String? get sessionId => _sessionId;
  String? get userId => _userId;
  String? get patientName => _patientName;
  Duration get duration => _duration;
  double get audioLevel => _audioLevel;
  bool get isRecording => _state == RecordingState.recording;
  bool get isPaused => _state == RecordingState.paused;
  int get pendingChunksCount => _pendingChunks.length;

  Future<int> get totalPendingChunksCount async {
    final diskCount = await _chunkStore.getPendingChunkCount();
    return _pendingChunks.length + diskCount;
  }

  bool get isOnline => _isOnline;
  bool get isInterrupted => _isInterrupted;

  set isOnline(bool value) {
    _isOnline = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      // Initialize connectivity service
      await _connectivityService.initialize();

      final success = await _audioService.initialize();
      if (!success) {
        _state = RecordingState.error;
        notifyListeners();
        return;
      }
    } catch (e) {
      // print('Failed to initialize audio service: $e');
      _state = RecordingState.error;
      notifyListeners();
      return;
    }

    // Listen to audio levels
    _audioService.audioLevelStream.listen((level) {
      _audioLevel = level;
      notifyListeners();
    });

    // Listen to recorder state changes
    _audioService.recorderStateStream.listen((recorderState) {
      switch (recorderState) {
        case RecorderState.recording:
          _state = RecordingState.recording;
          break;
        case RecorderState.paused:
          _state = RecordingState.paused;
          break;
        case RecorderState.stopped:
          _state = RecordingState.stopped;
          break;
        case RecorderState.error:
          _state = RecordingState.error;
          break;
      }
      notifyListeners();
    });

    // Monitor connectivity with enhanced handling
    _connectivityService.connectivityStream.listen((isOnline) {
      final wasOnline = _isOnline;
      _isOnline = isOnline;

      if (!wasOnline && _isOnline) {
        // Connection restored, try to upload pending chunks with delay
        Future.delayed(const Duration(seconds: 2), () {
          _retryPendingUploads();
        });
      }
      notifyListeners();
    });

    // Initialize current connectivity once at startup
    _initConnectivity();

    // Load any pending chunks from disk (survive app restarts)
    _loadPendingFromDisk();

    // Clean up old chunks on startup
    _chunkStore.cleanupOldChunks();
  }

  Future<void> _initConnectivity() async {
    try {
      _isOnline = _connectivityService.isOnline;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> startRecording({
    required String patientId,
    required String patientName,
    required String userId,
  }) async {
    try {
      _state = RecordingState.starting;
      notifyListeners();

      // Create Firebase session first
      String firebaseSessionId;
      try {
        firebaseSessionId = await FirebaseService.createRecordingSession(
          patientId: patientId,
          patientName: patientName,
          userId: userId,
        );
      } catch (e) {
        // print('Failed to create Firebase session: $e');
        firebaseSessionId =
            'firebase_offline_${DateTime.now().millisecondsSinceEpoch}';
      }

      // Create API session with fallback for offline mode
      try {
        _sessionId = await ApiService.createSession(
          patientId: patientId,
          userId: userId,
          patientName: patientName,
        );
      } catch (e) {
        // print('Failed to create API session, using offline mode: $e');
        // Use Firebase session ID as fallback
        _sessionId = firebaseSessionId;
      }

      _userId = userId;
      _patientName = patientName;
      _startTime = DateTime.now();
      _lastUploadedChunkNumber = 0;
      _lastGcsPath = null;
      _lastPublicUrl = null;

      // Start audio recording
      final success = await _audioService.startRecording(
        sessionId: _sessionId!,
        onChunkReady: _handleAudioChunk,
        onInterruption: handleInterruption,
        onInterruptionEnd: handleInterruptionEnd,
      );

      if (success) {
        _state = RecordingState.recording;
        _startDurationTimer();
      } else {
        _state = RecordingState.error;
        // Update Firebase session status to error
        try {
          await FirebaseService.updateRecordingSession(
            sessionId: firebaseSessionId,
            status: 'error',
          );
        } catch (e) {
          // print('Failed to update Firebase session status: $e');
        }
      }
      notifyListeners();
    } catch (e) {
      // print('Error starting recording: $e');
      _state = RecordingState.error;
      notifyListeners();
    }
  }

  Future<void> pauseRecording() async {
    await _audioService.pauseRecording();
  }

  Future<void> resumeRecording() async {
    await _audioService.resumeRecording();
    _isInterrupted = false;
    notifyListeners();
  }

  Future<void> handleInterruption() async {
    if (_state == RecordingState.recording) {
      _isInterrupted = true;
      await pauseRecording();
      notifyListeners();
    }
  }

  Future<void> handleInterruptionEnd() async {
    if (_isInterrupted && _state == RecordingState.paused) {
      await resumeRecording();
    }
  }

  Future<void> stopRecording() async {
    try {
      await _audioService.stopRecording();

      // Mark session complete using the last uploaded chunk info, if present
      if (_sessionId != null &&
          _lastUploadedChunkNumber > 0 &&
          _lastGcsPath != null &&
          _lastPublicUrl != null) {
        try {
          await ApiService.notifyChunkUploaded(
            sessionId: _sessionId!,
            gcsPath: _lastGcsPath!,
            chunkNumber: _lastUploadedChunkNumber,
            isLast: true,
            totalChunks: _lastUploadedChunkNumber,
            publicUrl: _lastPublicUrl!,
          );
        } catch (e) {
          // print('Error sending final notify: $e');
        }
      }

      // Update Firebase session status to completed
      if (_sessionId != null && _sessionId!.startsWith('firebase_')) {
        try {
          await FirebaseService.updateRecordingSession(
            sessionId: _sessionId!,
            status: 'completed',
            totalChunks: _lastUploadedChunkNumber,
            endTime: DateTime.now().toIso8601String(),
          );
        } catch (e) {
          // print('Failed to update Firebase session status: $e');
        }
      }

      _state = RecordingState.stopped;

      // Clean up any remaining chunks for this session
      if (_sessionId != null) {
        await _chunkStore.removeAllForSession(_sessionId!);
      }

      _sessionId = null;
      _userId = null;
      _patientName = null;
      _startTime = null;
      _duration = Duration.zero;
      _lastUploadedChunkNumber = 0;
      _lastGcsPath = null;
      _lastPublicUrl = null;
      _isInterrupted = false;
      notifyListeners();
    } catch (e) {
      // print('Error stopping recording: $e');
      _state = RecordingState.error;
      notifyListeners();
    }
  }

  void _handleAudioChunk(
    String sessionId,
    int chunkNumber,
    Uint8List audioData,
  ) async {
    try {
      if (_isOnline) {
        await _uploadChunk(sessionId, chunkNumber, audioData);
      } else {
        // Store chunk for later upload
        await _persistPendingChunk(sessionId, chunkNumber, audioData);
        notifyListeners();
      }
    } catch (e) {
      // print('Error handling audio chunk: $e');
      // Store as pending chunk on error
      await _persistPendingChunk(sessionId, chunkNumber, audioData);
      notifyListeners();
    }
  }

  Future<void> _uploadChunk(
    String sessionId,
    int chunkNumber,
    Uint8List audioData,
  ) async {
    // Get presigned URL
    final presignedResponse = await ApiService.getPresignedUrl(
      sessionId: sessionId,
      chunkNumber: chunkNumber,
    );

    // Upload chunk
    await ApiService.uploadChunk(
      presignedUrl: presignedResponse.url,
      audioData: audioData,
    );

    // Notify backend
    await ApiService.notifyChunkUploaded(
      sessionId: sessionId,
      gcsPath: presignedResponse.gcsPath,
      chunkNumber: chunkNumber,
      isLast: false, // We'll handle this differently in real implementation
      totalChunks: 0, // Calculate based on recording duration
      publicUrl: presignedResponse.publicUrl,
    );

    // print('Chunk $chunkNumber uploaded successfully for session $sessionId');
    _lastUploadedChunkNumber = chunkNumber;
    _lastGcsPath = presignedResponse.gcsPath;
    _lastPublicUrl = presignedResponse.publicUrl;

    // After a successful upload, try any pending queued chunks if online
    if (_isOnline && _pendingChunks.isNotEmpty) {
      _retryPendingUploads();
    }
  }

  Future<void> _retryPendingUploads() async {
    if (!_isOnline) return; // Don't retry if still offline

    final inMemory = List<PendingChunk>.from(_pendingChunks);
    _pendingChunks.clear();
    // Load disk-backed entries
    final diskEntries = await _chunkStore.loadAll();

    // Retry in-memory first (likely newest) with exponential backoff
    for (final chunk in inMemory) {
      try {
        await _uploadChunkWithRetry(
          chunk.sessionId,
          chunk.chunkNumber,
          chunk.audioData,
        );
      } catch (e) {
        // print('Failed to retry chunk upload: $e');
        // Add back to pending if still failing
        _pendingChunks.add(chunk);
      }
    }

    // Retry disk-backed entries with exponential backoff
    for (final entry in diskEntries) {
      try {
        final bytes = await _chunkStore.readChunkBytes(entry);
        if (bytes == null) {
          await _chunkStore.remove(entry);
          continue;
        }
        await _uploadChunkWithRetry(entry.sessionId, entry.chunkNumber, bytes);
        await _chunkStore.remove(entry);
      } catch (e) {
        // print('Failed to retry disk chunk upload: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _uploadChunkWithRetry(
    String sessionId,
    int chunkNumber,
    Uint8List audioData,
  ) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        await _uploadChunk(sessionId, chunkNumber, audioData);
        return; // Success, exit retry loop
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          rethrow; // Re-throw if max retries exceeded
        }
        // Exponential backoff: wait 1s, 2s, 4s
        await Future.delayed(Duration(seconds: 1 << (retryCount - 1)));
      }
    }
  }

  void _startDurationTimer() {
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (_state == RecordingState.recording && _startTime != null) {
        _duration = DateTime.now().difference(_startTime!);
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _audioService.dispose();
    _connectivityService.dispose();
    super.dispose();
  }

  // Utility: format duration as HH:MM:SS
  String formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}

enum RecordingState { idle, starting, recording, paused, stopped, error }

class PendingChunk {
  final String sessionId;
  final String userId;
  final int chunkNumber;
  final Uint8List audioData;
  final DateTime timestamp;

  PendingChunk({
    required this.sessionId,
    required this.userId,
    required this.chunkNumber,
    required this.audioData,
    required this.timestamp,
  });
}

extension _RecordingProviderDisk on RecordingProvider {
  Future<void> _loadPendingFromDisk() async {
    try {
      final diskEntries = await _chunkStore.loadAll();
      if (diskEntries.isNotEmpty) {
        // Keep only a lightweight counter in memory; actual bytes remain on disk
        // Note: notifyListeners() will be called by the calling method
      }
    } catch (e) {
      // print('Failed loading pending chunks from disk: $e');
    }
  }

  Future<void> _persistPendingChunk(
    String sessionId,
    int chunkNumber,
    Uint8List audioData,
  ) async {
    try {
      // Write to disk first to survive process death
      await _chunkStore.writeChunk(
        sessionId: sessionId,
        userId: _userId ?? 'unknown',
        chunkNumber: chunkNumber,
        bytes: audioData,
      );
      // Also keep in-memory for quick retry if still running
      _pendingChunks.add(
        PendingChunk(
          sessionId: sessionId,
          userId: _userId ?? 'unknown',
          chunkNumber: chunkNumber,
          audioData: audioData,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      // print('Failed to persist pending chunk: $e');
    }
  }
}
