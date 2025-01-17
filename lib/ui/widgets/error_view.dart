import 'package:flutter/material.dart';
import '../../../services/video_generation_service.dart';

class ErrorView extends StatelessWidget {
  final VideoServiceError error;
  final String message;
  final VoidCallback? onRetry;

  const ErrorView({
    Key? key,
    required this.error,
    required this.message,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: _getErrorColor().withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getErrorIcon(),
            color: _getErrorColor(),
            size: 48,
          ),
          SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          if (onRetry != null) ...[
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh),
              label: Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _getErrorColor().withOpacity(0.1),
                foregroundColor: _getErrorColor(),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getErrorColor() {
    switch (error) {
      case VideoServiceError.apiKeyMissing:
        return Colors.orange;
      case VideoServiceError.networkError:
        return Colors.red;
      case VideoServiceError.serverError:
        return Colors.red;
      case VideoServiceError.timeoutError:
        return Colors.orange;
      case VideoServiceError.unknownError:
        return Colors.red;
      case VideoServiceError.rateLimitExceeded:
        return Colors.orange;
      case VideoServiceError.invalidBrandId:
        return Colors.red;
      case VideoServiceError.generationLimitExceeded:
        return Colors.orange;
      case VideoServiceError.maxQueueReached:
        return Colors.orange;
    }
  }

  IconData _getErrorIcon() {
    switch (error) {
      case VideoServiceError.apiKeyMissing:
        return Icons.vpn_key;
      case VideoServiceError.networkError:
        return Icons.wifi_off;
      case VideoServiceError.serverError:
        return Icons.error;
      case VideoServiceError.timeoutError:
        return Icons.timer_off;
      case VideoServiceError.unknownError:
        return Icons.warning;
      case VideoServiceError.rateLimitExceeded:
        return Icons.speed;
      case VideoServiceError.invalidBrandId:
        return Icons.error;
      case VideoServiceError.generationLimitExceeded:
        return Icons.block;
      case VideoServiceError.maxQueueReached:
        return Icons.queue;
    }
  }
} 