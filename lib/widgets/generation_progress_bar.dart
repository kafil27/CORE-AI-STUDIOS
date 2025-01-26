import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class GenerationProgressBar extends StatefulWidget {
  final double progress;
  final String status;
  final bool showLabel;
  final double height;

  const GenerationProgressBar({
    super.key,
    required this.progress,
    required this.status,
    this.showLabel = true,
    this.height = 4,
  });

  @override
  State<GenerationProgressBar> createState() => _GenerationProgressBarState();
}

class _GenerationProgressBarState extends State<GenerationProgressBar> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _shimmerController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) return Colors.green.shade400;
    if (progress >= 0.7) return Colors.blue.shade400;
    if (progress >= 0.4) return Colors.amber.shade400;
    return Colors.blue.shade400;
  }

  IconData _getStatusIcon(double progress) {
    if (progress >= 1.0) return Icons.check_circle;
    if (progress >= 0.7) return Icons.autorenew;
    if (progress >= 0.4) return Icons.pending;
    return Icons.hourglass_empty;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  _getStatusIcon(widget.progress),
                  size: 16,
                  color: _getProgressColor(widget.progress),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.status,
                  style: TextStyle(
                    fontSize: 13,
                    color: _getProgressColor(widget.progress),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(widget.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 13,
                    color: _getProgressColor(widget.progress),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(widget.height),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.height),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getProgressColor(widget.progress).withOpacity(0.7),
                        _getProgressColor(widget.progress),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  widthFactor: widget.progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getProgressColor(widget.progress).withOpacity(0.7),
                          _getProgressColor(widget.progress),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
                if (widget.progress < 1.0)
                  AnimatedBuilder(
                    animation: _shimmerAnimation,
                    builder: (context, child) {
                      return FractionallySizedBox(
                        widthFactor: widget.progress.clamp(0.0, 1.0),
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return ui.Gradient.linear(
                              Offset(bounds.width * _shimmerAnimation.value, 0),
                              Offset(bounds.width * (_shimmerAnimation.value + 0.5), 0),
                              [
                                Colors.white.withOpacity(0.0),
                                Colors.white.withOpacity(0.3),
                                Colors.white.withOpacity(0.0),
                              ],
                              [0.0, 0.5, 1.0],
                            );
                          },
                          blendMode: BlendMode.srcIn,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _getProgressColor(widget.progress),
                                  _getProgressColor(widget.progress).withOpacity(0.7),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
} 