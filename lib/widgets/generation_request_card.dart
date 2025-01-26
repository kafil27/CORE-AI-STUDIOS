import 'package:flutter/material.dart';
import '../models/generation_request.dart';
import '../models/generation_type.dart' show GenerationStatus;

class GenerationRequestCard extends StatelessWidget {
  final GenerationRequest request;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final bool showProgress;
  final bool showControls;
  final bool isExpanded;

  const GenerationRequestCard({
    super.key,
    required this.request,
    this.onRetry,
    this.onCancel,
    this.showProgress = true,
    this.showControls = true,
    this.isExpanded = false,
  });

  Color _getStatusColor() => switch (request.status) {
    GenerationStatus.queued => Colors.orange,
    GenerationStatus.pending => Colors.orange,
    GenerationStatus.processing => Colors.blue,
    GenerationStatus.completed => Colors.green,
    GenerationStatus.failed => Colors.red,
    GenerationStatus.cancelled => Colors.grey,
  };

  IconData _getStatusIcon() => switch (request.status) {
    GenerationStatus.queued => Icons.hourglass_empty,
    GenerationStatus.pending => Icons.pending,
    GenerationStatus.processing => Icons.sync,
    GenerationStatus.completed => Icons.check_circle,
    GenerationStatus.failed => Icons.error,
    GenerationStatus.cancelled => Icons.cancel,
  };

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withAlpha(76),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withAlpha(128),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getStatusIcon(),
                            size: 16,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            request.status.value,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (showControls) ...[
                      if (request.canRetry && onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                          ),
                        ),
                      if (request.canCancel && onCancel != null)
                        TextButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                    ],
                  ],
                ),
                if (isExpanded || request.prompt.length <= 100) ...[
                  const SizedBox(height: 8),
                  Text(
                    request.prompt,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    '${request.prompt.substring(0, 100)}...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
                if (showProgress && request.isInProgress) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: (request.progress ?? 0) / 100,
                    backgroundColor: Colors.grey[800],
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ],
                if (request.error != null && isExpanded) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withAlpha(76),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.error ?? 'Unknown error',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (request.result != null && isExpanded) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: NetworkImage(request.result ?? ''),
                        fit: BoxFit.cover,
                        onError: (_, __) => const Icon(Icons.error),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
} 