import 'package:flutter/material.dart';

class GenerationProgressBar extends StatelessWidget {
  final double progress;
  final String status;
  final bool showLabel;
  final double height;
  final Color? startColor;
  final Color? endColor;

  const GenerationProgressBar({
    Key? key,
    required this.progress,
    required this.status,
    this.showLabel = true,
    this.height = 4,
    this.startColor,
    this.endColor,
  }) : super(key: key);

  Color _getStartColor(BuildContext context) {
    if (status.toLowerCase().contains('queue')) {
      return Colors.orange;
    } else if (status.toLowerCase().contains('initializing')) {
      return Colors.blue;
    } else if (status.toLowerCase().contains('processing')) {
      return Colors.purple;
    } else if (status.toLowerCase().contains('complete')) {
      return Colors.green;
    }
    return startColor ?? Theme.of(context).primaryColor;
  }

  Color _getEndColor(BuildContext context) {
    if (status.toLowerCase().contains('queue')) {
      return Colors.deepOrange;
    } else if (status.toLowerCase().contains('initializing')) {
      return Colors.lightBlue;
    } else if (status.toLowerCase().contains('processing')) {
      return Colors.deepPurple;
    } else if (status.toLowerCase().contains('complete')) {
      return Colors.lightGreen;
    }
    return endColor ?? Theme.of(context).primaryColor.withOpacity(0.7);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final progressWidth = screenWidth * progress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _getStartColor(context),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getStartColor(context).withOpacity(0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: Stack(
              children: [
                // Background gradient
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.grey[900]!,
                        Colors.grey[850]!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Progress gradient with animated glow
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  width: progressWidth,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getStartColor(context),
                        _getEndColor(context),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _getStartColor(context).withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
                // Animated shimmer effect
                if (progress < 1.0)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: -screenWidth, end: screenWidth),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) => Positioned(
                      left: value,
                      child: Container(
                        height: height,
                        width: screenWidth * 0.2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0),
                              Colors.white.withOpacity(0.2),
                              Colors.white.withOpacity(0),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                    onEnd: () {},
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
} 