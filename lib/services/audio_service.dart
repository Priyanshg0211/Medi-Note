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
  double _smoothedLevel = 0.0;
  bool _isStopping = false;
  bool _isProcessingChunk = false;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Callback for interruption handling
  Function()? _onInterruption;
  Function()? _onInterruptionEnd;

  String? _currentSessionId;
  String? _currentFilePath;
  Timer? _chunkTimer;
  int _chunkCounter = 1;
  int _lastProcessedBytes = 0;
  Stream<double> get audioLevelStream =>
      _levelController?.stream ?? Stream.empty();
  Stream<RecorderState> get recorderStateStream =>
      _stateController?.stream ?? Stream.empty();

  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        return true;
      }

      final micPermission = await Permission.microphone.request();
      final phonePermission = await Permission.phone.request();

      if (micPermission != PermissionStatus.granted) {
        return false;
      }

      // Phone permission is optional for call detection, but recommended
      if (phonePermission != PermissionStatus.granted) {
        // print('Phone state permission denied - call interruption detection may not work');
      }
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker |
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: true,
        ),
      );

      _recorder = FlutterSoundRecorder();
      _player = FlutterSoundPlayer();

      try {
        await _recorder!.openRecorder();
        try {
          await _recorder!.setSubscriptionDuration(
            const Duration(milliseconds: 100),
          );
        } catch (_) {}
      } catch (e) {
        return false;
      }

      try {
        await _player!.openPlayer();
      } catch (e) {}

      _levelController = StreamController<double>.broadcast();
      _stateController = StreamController<RecorderState>.broadcast();

      _isInitialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> startRecording({
    required String sessionId,
    required Function(String, int, Uint8List) onChunkReady,
    Function()? onInterruption,
    Function()? onInterruptionEnd,
  }) async {
    if (!_isInitialized || _recorder == null) {
      throw Exception('AudioService not initialized');
    }

    try {
      _currentSessionId = sessionId;
      _chunkCounter = 1;
      _lastProcessedBytes = 0;
      _isStopping = false;
      _isProcessingChunk = false;
      _onInterruption = onInterruption;
      _onInterruptionEnd = onInterruptionEnd;

      final tempDir = await getTemporaryDirectory();
      _currentFilePath = '${tempDir.path}/recording_$sessionId.wav';

      await _recorder!.startRecorder(
        toFile: _currentFilePath,
        codec: Codec.pcm16WAV,
        numChannels: 1,
        sampleRate: 16000,
        bitRate: 128000,
      );

      _recorderSubscription = _recorder!.onProgress!.listen((e) {
        const double minDb = -60.0;
        const double maxDb = 0.0;
        final double levelDb = (e.decibels ?? minDb).clamp(minDb, maxDb);
        double instant = (levelDb - minDb) / (maxDb - minDb);
        if (!instant.isFinite) instant = 0.0;

        const double attack = 0.6;
        const double release = 0.15;
        if (instant > _smoothedLevel) {
          _smoothedLevel = attack * instant + (1.0 - attack) * _smoothedLevel;
        } else {
          _smoothedLevel = release * instant + (1.0 - release) * _smoothedLevel;
        }

        final double gated = _smoothedLevel < 0.02 ? 0.0 : _smoothedLevel;
        _levelController?.add(gated.clamp(0.0, 1.0));
      });

      _chunkTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        await _processAudioChunk(onChunkReady);
      });

      _stateController?.add(RecorderState.recording);

      try {
        final session = await AudioSession.instance;

        // Handle audio becoming noisy (e.g., headphones disconnected)
        session.becomingNoisyEventStream.listen((_) async {
          try {
            if (_recorder?.isRecording == true) {
              await pauseRecording();
            }
          } catch (_) {}
        });

        // Handle audio interruptions (phone calls, other apps)
        session.interruptionEventStream.listen((event) async {
          if (event.begin) {
            // Interruption started (phone call, other audio app)
            try {
              if (_recorder?.isRecording == true) {
                print('Audio interruption detected - pausing recording');
                await pauseRecording();
                _onInterruption?.call();
              }
            } catch (e) {
              print('Error handling interruption: $e');
            }
          } else {
            // Interruption ended
            print('Audio interruption ended - type: ${event.type}');
            if (event.type == sess.AudioInterruptionType.pause) {
              // Resume recording after interruption ends
              try {
                if (_recorder?.isPaused == true) {
                  print('Resuming recording after pause interruption');
                  await resumeRecording();
                  _onInterruptionEnd?.call();
                }
              } catch (e) {
                print('Error resuming after pause: $e');
              }
            } else if (event.type == sess.AudioInterruptionType.duck) {
              // Audio was ducked (lowered volume) - resume if needed
              try {
                if (_recorder?.isPaused == true) {
                  print('Resuming recording after duck interruption');
                  await resumeRecording();
                  _onInterruptionEnd?.call();
                }
              } catch (e) {
                print('Error resuming after duck: $e');
              }
            }
          }
        });
      } catch (_) {}
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _processAudioChunk(
    Function(String, int, Uint8List) onChunkReady,
  ) async {
    if (_currentFilePath == null || _currentSessionId == null) return;
    if (_isStopping || _isProcessingChunk) return;
    if (_recorder == null) return;

    try {
      _isProcessingChunk = true;

      final bool canPause = (_recorder!.isRecording == true);
      if (canPause) {
        await _recorder!.pauseRecorder();
      }

      final file = File(_currentFilePath!);
      if (await file.exists()) {
        final currentFileSize = await file.length();

        if (currentFileSize > _lastProcessedBytes) {
          final audioBytes = await file.readAsBytes();

          final newDataStart = _lastProcessedBytes;
          final newDataLength = currentFileSize - _lastProcessedBytes;

          if (newDataLength > 0) {
            final chunkData = audioBytes.sublist(
              newDataStart,
              newDataStart + newDataLength,
            );

            onChunkReady(
              _currentSessionId!,
              _chunkCounter,
              Uint8List.fromList(chunkData),
            );
            _chunkCounter++;
            _lastProcessedBytes = currentFileSize;
          }
        }
      }

      if (canPause && !_isStopping) {
        await _recorder!.resumeRecorder();
      }
    } catch (e) {
      // Handle error silently
    } finally {
      _isProcessingChunk = false;
    }
  }

  Future<void> pauseRecording() async {
    if (_recorder?.isPaused == false) {
      await _recorder!.pauseRecorder();
      _stateController?.add(RecorderState.paused);
    }
  }

  Future<void> resumeRecording() async {
    if (_recorder?.isPaused == true) {
      await _recorder!.resumeRecorder();
      _stateController?.add(RecorderState.recording);
    }
  }

  Future<void> stopRecording() async {
    try {
      _isStopping = true;
      _chunkTimer?.cancel();
      _chunkTimer = null;

      final int startWaitMs = DateTime.now().millisecondsSinceEpoch;
      while (_isProcessingChunk &&
          DateTime.now().millisecondsSinceEpoch - startWaitMs < 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      if (_recorder != null) {
        try {
          if (_recorder!.isRecording == true || _recorder!.isPaused == true) {
            await _recorder!.stopRecorder();
          }
        } catch (e) {}
      }

      await _recorderSubscription?.cancel();
      _recorderSubscription = null;

      _stateController?.add(RecorderState.stopped);

      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _currentSessionId = null;
      _currentFilePath = null;
      _chunkCounter = 1;
      _lastProcessedBytes = 0;
      _isStopping = false;
      _isProcessingChunk = false;
    } catch (e) {}
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

enum RecorderState { stopped, recording, paused, error }
