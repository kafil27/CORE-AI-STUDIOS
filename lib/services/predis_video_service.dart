import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../config/ai_service_config.dart';
import '../models/generation_request.dart';
import '../models/generation_type.dart';
import 'notification_service.dart';

enum PredisVideoError {
  invalidApiKey,
  invalidBrandId,
  serverError,
  networkError,
  rateLimitExceeded,
  invalidInput,
  unknown,
}

class PredisVideoService {
  final AIServiceConfig _config;
  bool _isInitialized = false;
  
  PredisVideoService() : _config = AIServiceFactory.getConfig(AIServiceType.predisAI) {
    _validateConfig();
  }

  void _validateConfig() {
    if (_config.apiKey.isEmpty) {
      debugPrint('WARNING: Predis API key is not set. Please check your .env file');
    }
    if (_config.defaultParams['brand_id']?.isEmpty ?? true) {
      debugPrint('WARNING: Predis Brand ID is not set. Please check your .env file');
    }
    _isInitialized = _config.apiKey.isNotEmpty && 
                     (_config.defaultParams['brand_id']?.isNotEmpty ?? false);
  }

  Future<String?> generateVideo({
    required BuildContext context,
    required String prompt,
    Map<String, dynamic>? additionalParams,
  }) async {
    if (!_isInitialized) {
      NotificationService.showError(
        context: context,
        title: 'Configuration Error',
        message: 'API key or Brand ID not configured properly',
        technicalDetails: 'Please check your .env file and ensure PREDIS_API_KEY and PREDIS_BRAND_ID are set.',
      );
      return null;
    }

    try {
      debugPrint('Generating video with prompt: $prompt');
      final response = await http.post(
        Uri.parse('${_config.baseUrl}/create-content'),
        headers: _config.headers,
        body: jsonEncode({
          ..._config.defaultParams,
          'prompt': prompt,
          'content_type': 'video',
          ...?additionalParams,
        }),
      );

      final data = jsonDecode(response.body);
      debugPrint('API Response Status: ${response.statusCode}');
      debugPrint('API Response Body: ${response.body}');
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        NotificationService.showSuccess(
          context: context,
          title: 'Success',
          message: 'Video generation started successfully',
        );
        return data['data']['video_url'];
      } else {
        _handleError(response.statusCode, data, context);
        return null;
      }
    } catch (e) {
      debugPrint('Error generating video: $e');
      NotificationService.showError(
        context: context,
        title: 'Video Generation Error',
        message: 'Failed to generate video',
        technicalDetails: e.toString(),
      );
      return null;
    }
  }

  Future<List<GenerationRequest>> getRecentVideos({
    required BuildContext context,
    int limit = 5,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${_config.baseUrl}/get-all-posts').replace(
          queryParameters: {
            ..._config.defaultParams,
            'limit': limit.toString(),
            'content_type': 'video',
          },
        ),
        headers: _config.headers,
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        if (data['status'] == 'success') {
          final List<dynamic> videos = data['data'];
          return videos.map((video) => GenerationRequest(
            id: video['id'].toString(),
            userId: video['user_id'].toString(),
            type: GenerationType.video,
            prompt: video['prompt'],
            status: _mapPredisStatus(video['status']),
            createdAt: DateTime.parse(video['created_at']),
            updatedAt: DateTime.parse(video['updated_at']),
            priority: 1,
            attempts: 0,
            maxAttempts: 3,
            progress: _calculateProgress(video['status']),
            retryCount: 0,
            metadata: {
              'video_url': video['video_url'],
              'thumbnail_url': video['thumbnail_url'],
            },
            tokensUsed: video['tokens_used'] ?? 0,
            result: video['video_url'],
          )).toList();
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch videos');
        }
      } else {
        _handleError(response.statusCode, data, context);
        return [];
      }
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Error',
        message: 'Failed to fetch recent videos',
        technicalDetails: e.toString(),
      );
      return [];
    }
  }

  GenerationStatus _mapPredisStatus(String status) {
    switch (status.toLowerCase()) {
      case 'queued':
        return GenerationStatus.queued;
      case 'processing':
        return GenerationStatus.processing;
      case 'completed':
        return GenerationStatus.completed;
      case 'failed':
        return GenerationStatus.failed;
      default:
        return GenerationStatus.pending;
    }
  }

  int _calculateProgress(String status) {
    switch (status.toLowerCase()) {
      case 'queued':
        return 0;
      case 'processing':
        return 50;
      case 'completed':
        return 100;
      case 'failed':
        return 0;
      default:
        return 0;
    }
  }

  void _handleError(int statusCode, Map<String, dynamic> data, BuildContext context) {
    String message = data['message'] ?? 'Unknown error occurred';
    String details = data['details'] ?? '';
    debugPrint('Handling error: Status=$statusCode, Message=$message, Details=$details');

    switch (statusCode) {
      case 401:
        NotificationService.showError(
          context: context,
          title: 'Authentication Error',
          message: 'Invalid API key. Please check your configuration.',
          technicalDetails: 'Status: $statusCode\nDetails: $details',
        );
        break;
      case 403:
        NotificationService.showError(
          context: context,
          title: 'Access Denied',
          message: 'Invalid brand ID or insufficient permissions. Please check your configuration.',
          technicalDetails: 'Status: $statusCode\nDetails: $details',
        );
        break;
      case 429:
        NotificationService.showError(
          context: context,
          title: 'Rate Limit Exceeded',
          message: 'Too many requests. Please try again later.',
          technicalDetails: 'Status: $statusCode\nDetails: $details',
        );
        break;
      case 400:
        NotificationService.showError(
          context: context,
          title: 'Invalid Request',
          message: message,
          technicalDetails: 'Status: $statusCode\nDetails: $details',
        );
        break;
      default:
        NotificationService.showError(
          context: context,
          title: 'Server Error',
          message: 'An unexpected error occurred. Please try again.',
          technicalDetails: 'Status: $statusCode\nMessage: $message\nDetails: $details',
        );
    }
  }
} 