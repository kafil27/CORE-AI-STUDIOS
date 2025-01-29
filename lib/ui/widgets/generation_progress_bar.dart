import 'package:flutter/material.dart';
import 'dart:ui' as ui;

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
    if (status.toLowerCase().contains('queued')) {
      return Colors.orange;
    } else if (status.toLowerCase().contains('generating')) {
      return Colors.blue;
    } else if (status.toLowerCase().contains('processing')) {
      return Colors.purple;
    }
    return startColor ?? Theme.of(context).primaryColor;
  }

  Color _getEndColor(BuildContext context) {
    if (status.toLowerCase().contains('queued')) {
      return Colors.deepOrange;
    } else if (status.toLowerCase().contains('generating')) {
      return Colors.lightBlue;
    } else if (status.toLowerCase().contains('processing')) {
      return Colors.deepPurple;
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
                  status,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(height),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getStartColor(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
} 