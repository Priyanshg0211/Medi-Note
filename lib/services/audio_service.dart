import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart' as sess;

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  StreamSubscription? _recorderSubscription;
  StreamController<double>? _levelController;
  StreamController<RecorderState>? _stateController;
  double _smoothedLevel = 0.0; // 0..1 smoothed envelope
  bool _isStopping = false;
  bool _isProcessingChunk = false;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String? _currentSessionId;
  String? _currentFilePath;
  Timer? _chunkTimer;
  int _chunkCounter = 1;
  int _lastProcessedBytes = 0; // Track last processed file size for incremental chunks

  // Stream controllers
  Stream<double> get audioLevelStream =>
      _levelController?.stream ?? Stream.empty();
  Stream<RecorderState> get recorderStateStream =>
      _stateController?.stream ?? Stream.empty();

  Future<bool> initialize() async {
    try {
      // Request permissions
      final micPermission = await Permission.microphone.request();

      if (micPermission != PermissionStatus.granted) {
        throw Exception('Microphone permission not granted');
      }

      // Initialize audio session
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.defaultMode, // Fixed: changed from 'default'
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      // Initialize recorder and player
      _recorder = FlutterSoundRecorder();
      _player = FlutterSoundPlayer();

      await _recorder!.openRecorder();
      // Emit progress frequently for responsive UI
      try {
        await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 100));
      } catch (_) {
        // Some platforms may not support; ignore safely
      }
      await _player!.openPlayer();

      // Initialize stream controllers
      _levelController = StreamController<double>.broadcast();
      _stateController = StreamController<RecorderState>.broadcast();

      _isInitialized = true;
      print('AudioService initialized successfully');
      return true;
    } catch (e) {
      print('AudioService initialization failed: $e');
      return false;
    }
  }

  Future<bool> startRecording({
    required String sessionId,
    required Function(String, int, Uint8List) onChunkReady,
  }) async {
    if (!_isInitialized || _recorder == null) {
      throw Exception('AudioService not initialized');
    }

    try {
      _currentSessionId = sessionId;
      _chunkCounter = 1;
      _lastProcessedBytes = 0; // Reset for new recording
      _isStopping = false;
      _isProcessingChunk = false;

      // Get temporary directory for audio file
      final tempDir = await getTemporaryDirectory();
      _currentFilePath = '${tempDir.path}/recording_$sessionId.wav';

      // Start recording with specific codec settings
      await _recorder!.startRecorder(
        toFile: _currentFilePath,
        codec: Codec.pcm16WAV,
        numChannels: 1,
        sampleRate: 16000,
        bitRate: 128000,
      );

      // Listen to audio levels for visualization
      // Increase progress emission rate for more responsive level UI
      _recorderSubscription = _recorder!.onProgress!.listen((e) {
        // Map decibels to 0..1 using calibrated range, then apply fast attack / slow release
        const double minDb = -60.0; // noise floor
        const double maxDb = 0.0;   // loud speech
        final double levelDb = (e.decibels ?? minDb).clamp(minDb, maxDb);
        double instant = (levelDb - minDb) / (maxDb - minDb);
        if (!instant.isFinite) instant = 0.0;

        // Envelope smoothing: rise quickly, fall slowly
        const double attack = 0.6;  // 60% new value per tick when rising
        const double release = 0.15; // 15% new value per tick when falling
        if (instant > _smoothedLevel) {
          _smoothedLevel = attack * instant + (1.0 - attack) * _smoothedLevel;
        } else {
          _smoothedLevel = release * instant + (1.0 - release) * _smoothedLevel;
        }

        // Small gate to zero-out very quiet noise while still showing soft speech
        final double gated = _smoothedLevel < 0.02 ? 0.0 : _smoothedLevel;
        _levelController?.add(gated.clamp(0.0, 1.0));
      });

      // Start chunked streaming every 5 seconds
      _chunkTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        await _processAudioChunk(onChunkReady);
      });

      _stateController?.add(RecorderState.recording);

      // React to interruptions (phone calls, focus loss)
      try {
        final session = await AudioSession.instance;
        session.becomingNoisyEventStream.listen((_) async {
          try {
            await pauseRecording();
          } catch (_) {}
        });
        session.interruptionEventStream.listen((event) async {
          if (event.begin) {
            try {
              await pauseRecording();
            } catch (_) {}
          } else {
            if (event.type == sess.AudioInterruptionType.pause) {
              try {
                await resumeRecording();
              } catch (_) {}
            }
          }
        });
      } catch (_) {}
      print('Recording started for session: $sessionId');
      return true;
    } catch (e) {
      print('Failed to start recording: $e');
      return false;
    }
  }

  Future<void> _processAudioChunk(Function(String, int, Uint8List) onChunkReady) async {
    if (_currentFilePath == null || _currentSessionId == null) return;
    if (_isStopping || _isProcessingChunk) return;
    if (_recorder == null) return;

    try {
      _isProcessingChunk = true;

      // Only process if recorder is active
      final bool canPause = (_recorder!.isRecording == true);
      if (canPause) {
        await _recorder!.pauseRecorder();
      }

      // Read the current audio file
      final file = File(_currentFilePath!);
      if (await file.exists()) {
        final currentFileSize = await file.length();
        
        // Only process if file has grown since last chunk
        if (currentFileSize > _lastProcessedBytes) {
          final audioBytes = await file.readAsBytes();
          
          // Extract only the new data since last chunk
          final newDataStart = _lastProcessedBytes;
          final newDataLength = currentFileSize - _lastProcessedBytes;
          
          if (newDataLength > 0) {
            final chunkData = audioBytes.sublist(
              newDataStart, 
              newDataStart + newDataLength
            );
            
            print('Sending chunk $_chunkCounter: ${chunkData.length} bytes (${newDataStart}-${newDataStart + newDataLength})');
            onChunkReady(_currentSessionId!, _chunkCounter, Uint8List.fromList(chunkData));
            _chunkCounter++;
            _lastProcessedBytes = currentFileSize;
          }
        } else {
          print('No new audio data to process');
        }
      }

      // Resume recording if we paused and not stopping
      if (canPause && !_isStopping) {
        await _recorder!.resumeRecorder();
      }
    } catch (e) {
      print('Error processing audio chunk: $e');
    } finally {
      _isProcessingChunk = false;
    }
  }

  Future<void> pauseRecording() async {
    if (_recorder?.isPaused == false) {
      await _recorder!.pauseRecorder();
      _stateController?.add(RecorderState.paused);
      print('Recording paused');
    }
  }

  Future<void> resumeRecording() async {
    if (_recorder?.isPaused == true) {
      await _recorder!.resumeRecorder();
      _stateController?.add(RecorderState.recording);
      print('Recording resumed');
    }
  }

  Future<void> stopRecording() async {
    try {
      _isStopping = true;
      // Cancel chunk timer
      _chunkTimer?.cancel();
      _chunkTimer = null;

      // Wait briefly if a chunk is processing to avoid race
      final int startWaitMs = DateTime.now().millisecondsSinceEpoch;
      while (_isProcessingChunk &&
          DateTime.now().millisecondsSinceEpoch - startWaitMs < 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Stop recording (idempotent)
      if (_recorder != null) {
        try {
          if (_recorder!.isRecording == true || _recorder!.isPaused == true) {
            await _recorder!.stopRecorder();
          }
        } catch (e) {
          // Some platforms may throw if already stopped
          print('stopRecorder ignored: $e');
        }
      }

      // Cancel subscription
      await _recorderSubscription?.cancel();
      _recorderSubscription = null;

      _stateController?.add(RecorderState.stopped);
      print('Recording stopped');

      // Clean up file
      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _currentSessionId = null;
      _currentFilePath = null;
      _chunkCounter = 1;
      _lastProcessedBytes = 0; // Reset for next recording
      _isStopping = false;
      _isProcessingChunk = false;
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }

  Future<void> dispose() async {
    await stopRecording();
    await _recorder?.closeRecorder();
    await _player?.closePlayer();
    await _levelController?.close();
    await _stateController?.close();

    _recorder = null;
    _player = null;
    _levelController = null;
    _stateController = null;
    _isInitialized = false;
  }
}

enum RecorderState {
  stopped,
  recording,
  paused,
  error,
}