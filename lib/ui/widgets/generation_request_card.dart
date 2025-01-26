import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/generation_request.dart';
import '../../models/generation_type.dart';
import '../../services/generation_request_service.dart';
import '../../services/downloads_service.dart';
import '../widgets/loading_overlay.dart';
import 'package:url_launcher/url_launcher.dart';

class GenerationRequestCard extends ConsumerWidget {
  final GenerationRequest request;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final bool showProgress;
  final bool showControls;
  final bool isExpanded;

  const GenerationRequestCard({
    Key? key,
    required this.request,
    this.onRetry,
    this.onCancel,
    this.showProgress = true,
    this.showControls = true,
    this.isExpanded = false,
  }) : super(key: key);

  Color _getStatusColor(GenerationStatus status) {
    return switch (status) {
      GenerationStatus.queued => Colors.orange,
      GenerationStatus.pending => Colors.blue,
      GenerationStatus.processing => Colors.amber,
      GenerationStatus.completed => Colors.green,
      GenerationStatus.failed => Colors.red,
      GenerationStatus.cancelled => Colors.grey,
    };
  }

  Widget _buildProgressIndicator() {
    if (!showProgress) return const SizedBox.shrink();

    if (request.isInProgress && request.progress != null) {
      return Column(
        children: [
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: request.progress! / 100,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(
              _getStatusColor(request.status),
            ),
          ),
          if (request.estimatedTimeRemaining != null) ...[
            const SizedBox(height: 4),
            Text(
              'Estimated time: ${request.timeRemaining}',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
          ],
        ],
      );
    }

    if (request.status == GenerationStatus.queued && request.queuePosition != null) {
      return Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Queue Position: #${request.queuePosition}',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildControls(BuildContext context) {
    if (!showControls) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (request.canRetry && onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.amber,
            ),
          ),
        if (request.canCancel && onCancel != null)
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
          ),
        if (request.isCompleted && request.result != null)
          TextButton.icon(
            onPressed: () async {
              final uri = Uri.parse(request.result!);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.green,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.grey[900],
      child: Padding(
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
                    color: _getStatusColor(request.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getStatusColor(request.status).withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        request.isCompleted
                            ? Icons.check_circle
                            : request.isFailed
                                ? Icons.error
                                : Icons.pending,
                        size: 16,
                        color: _getStatusColor(request.status),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        request.statusText,
                        style: TextStyle(
                          color: _getStatusColor(request.status),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '${request.type.toString().split('.').last.toUpperCase()} Generation',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (isExpanded || request.error != null) ...[
              const SizedBox(height: 16),
              Text(
                request.prompt,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
            if (request.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request.error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            _buildProgressIndicator(),
            if (showControls) ...[
              const SizedBox(height: 8),
              _buildControls(context),
            ],
          ],
        ),
      ),
    );
  }
} 