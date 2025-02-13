// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lottie/lottie.dart';
import '../../models/generation_request.dart';
import 'generation_progress_bar.dart';

class GenerationStatusCard extends StatelessWidget {
  final GenerationRequest request;
  final bool isExpanded;
  final VoidCallback? onCancel;

  const GenerationStatusCard({
    Key? key,
    required this.request,
    this.isExpanded = true,
    this.onCancel,
  }) : super(key: key);

  String _getStatusMessage() {
    switch (request.status.toLowerCase()) {
      case 'pending':
        return 'Added to queue...';
      case 'processing':
        return 'Generating your video...';
      case 'completed':
        return 'Generation completed!';
      case 'failed':
        return 'Generation failed';
      default:
        return 'Preparing...';
    }
  }

  Widget _buildStatusIcon() {
    switch (request.status.toLowerCase()) {
      case 'pending':
        return LoadingAnimationWidget.staggeredDotsWave(
          color: Colors.amber,
          size: 40,
        );
      case 'processing':
        return LoadingAnimationWidget.inkDrop(
          color: Colors.blue,
          size: 40,
        );
      case 'completed':
        return Icon(
          Icons.check_circle,
          color: Colors.green[400],
          size: 40,
        );
      case 'failed':
        return Icon(
          Icons.error,
          color: Colors.red[400],
          size: 40,
        );
      default:
        return LoadingAnimationWidget.discreteCircle(
          color: Colors.grey,
          size: 40,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildStatusIcon(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStatusMessage(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (request.queuePosition != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Queue Position: ${request.queuePosition}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onCancel != null && request.status.toLowerCase() == 'pending')
                IconButton(
                  icon: const Icon(Icons.cancel_outlined),
                  color: Colors.red[400],
                  onPressed: onCancel,
                ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 16),
            GenerationProgressBar(
              progress: (request.progress ?? 0) / 100,
              status: request.status,
              showLabel: true,
              startColor: request.status.toLowerCase() == 'processing' 
                ? Colors.blue 
                : Colors.amber,
              endColor: request.status.toLowerCase() == 'processing'
                ? Colors.lightBlue
                : Colors.deepOrange,
            ),
            if (request.estimatedTimeRemaining != null) ...[
              const SizedBox(height: 8),
              Text(
                'Estimated time remaining: ${request.estimatedTimeRemaining}s',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[400],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
} 