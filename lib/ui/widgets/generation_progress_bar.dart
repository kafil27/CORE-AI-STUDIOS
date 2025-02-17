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
     
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        Stack(
          children: [
            // Background
            Container(
              height: height,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(height),
              ),
            ),
            // Progress
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: height,
              width: MediaQuery.of(context).size.width * progress,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _getStartColor(context),
                    _getEndColor(context),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getStartColor(context).withOpacity(0.5),
                    blurRadius: 6,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
            // Shimmer effect
            if (progress < 1.0)
              _buildShimmerEffect(context),
          ],
        ),
      ],
    );
  }

  Widget _buildShimmerEffect(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: -constraints.maxWidth, end: constraints.maxWidth),
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOut,
          builder: (context, value, child) {
            return Positioned(
              left: value,
              child: Container(
                height: height,
                width: constraints.maxWidth * 0.7,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withOpacity(0),
                      Colors.white.withOpacity(0.3),
                      Colors.white.withOpacity(0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            );
          },
          onEnd: () {},
        );
      },
    );
  }
} 