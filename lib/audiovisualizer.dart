import 'package:flutter/material.dart';
import 'dart:math' as math;

class AudioVisualizerWidget extends StatefulWidget {
  final double audioLevel;
  final bool isRecording;
  final Color primaryColor;

  const AudioVisualizerWidget({
    super.key,
    required this.audioLevel,
    required this.isRecording,
    this.primaryColor = Colors.blue,
  });

  @override
  State<AudioVisualizerWidget> createState() => _AudioVisualizerWidgetState();
}

class _AudioVisualizerWidgetState extends State<AudioVisualizerWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  final List<double> _audioHistory = List.filled(50, 0.0);
  int _historyIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.isRecording) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(AudioVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Update audio history
    if (widget.audioLevel != oldWidget.audioLevel) {
      _audioHistory[_historyIndex] = widget.audioLevel;
      _historyIndex = (_historyIndex + 1) % _audioHistory.length;
    }

    // Handle animation state
    if (widget.isRecording && !oldWidget.isRecording) {
      _animationController.repeat();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            painter: AudioVisualizerPainter(
              audioHistory: _audioHistory,
              currentIndex: _historyIndex,
              audioLevel: widget.audioLevel,
              isRecording: widget.isRecording,
              animationValue: _animation.value,
              primaryColor: widget.primaryColor,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class AudioVisualizerPainter extends CustomPainter {
  final List<double> audioHistory;
  final int currentIndex;
  final double audioLevel;
  final bool isRecording;
  final double animationValue;
  final Color primaryColor;

  AudioVisualizerPainter({
    required this.audioHistory,
    required this.currentIndex,
    required this.audioLevel,
    required this.isRecording,
    required this.animationValue,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isRecording) {
      _drawIdleState(canvas, size);
      return;
    }

    _drawWaveform(canvas, size);
    _drawCurrentLevel(canvas, size);
  }

  void _drawIdleState(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw flat line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    // Draw microphone icon in center
    final iconSize = 24.0;
    final iconRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: iconSize,
      height: iconSize,
    );

    final iconPaint = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.fill;

    // Simple microphone shape
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: iconRect.center,
          width: iconSize * 0.4,
          height: iconSize * 0.6,
        ),
        const Radius.circular(8),
      ),
      iconPaint,
    );
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final barWidth = size.width / audioHistory.length;
    
    for (int i = 0; i < audioHistory.length; i++) {
      final dataIndex = (currentIndex - i) % audioHistory.length;
      final level = audioHistory[dataIndex];
      final opacity = math.max(0.1, 1.0 - (i / audioHistory.length));
      
      // Calculate bar height
      final barHeight = level * size.height * 0.8;
      final centerY = size.height / 2;
      
      // Color based on level and opacity
      Color barColor;
      if (level > 0.7) {
        barColor = Colors.red.withOpacity(opacity);
      } else if (level > 0.4) {
        barColor = Colors.orange.withOpacity(opacity);
      } else {
        barColor = primaryColor.withOpacity(opacity);
      }
      
      paint.color = barColor;
      
      final x = size.width - (i * barWidth);
      
      // Draw vertical bar
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  void _drawCurrentLevel(Canvas canvas, Size size) {
    // Draw current level indicator
    final levelPaint = Paint()
      ..color = primaryColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final levelHeight = audioLevel * size.height * 0.9;
    final centerY = size.height / 2;
    
    canvas.drawRect(
      Rect.fromLTWH(
        size.width - 10,
        centerY - levelHeight / 2,
        8,
        levelHeight,
      ),
      levelPaint,
    );

    // Draw pulsing circle for current level
    if (audioLevel > 0.1) {
      final pulsePaint = Paint()
        ..color = primaryColor.withOpacity(0.6 - (animationValue * 0.3))
        ..style = PaintingStyle.fill;

      final pulseRadius = 4 + (audioLevel * 8) + (animationValue * 4);
      
      canvas.drawCircle(
        Offset(size.width - 6, centerY),
        pulseRadius,
        pulsePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AudioVisualizerPainter oldDelegate) {
    return oldDelegate.audioLevel != audioLevel ||
           oldDelegate.animationValue != animationValue ||
           oldDelegate.isRecording != isRecording ||
           oldDelegate.currentIndex != currentIndex;
  }
}