import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import '../ui/widgets/custom_error_popup.dart';
import 'notification_service.dart';

enum VideoServiceError {
  apiKeyMissing,
  networkError,
  serverError,
  timeoutError,
  unknownError,
  rateLimitExceeded,
  invalidBrandId,
  generationLimitExceeded,
  maxQueueReached,
}

class VideoServiceException implements Exception {
  final VideoServiceError error;
  final String message;
  final String? technicalDetails;

  VideoServiceException(this.error, this.message, {this.technicalDetails}) {
    if (technicalDetails != null) {
      print('VideoService Error: $error');
      print('Technical Details: $technicalDetails');
    }
  }

  @override
  String toString() => message;
}

class VideoGenerationService {
  final String predisApiKey = dotenv.env['PREDIS_API_KEY'] ?? '';
  final String predisBrandId = dotenv.env['PREDIS_BRAND_ID'] ?? '';
  final String baseUrl = 'https://brain.predis.ai/predis_api/v1';
  final String webhookUrl = 'https://www.google.com/';
  final String predisBaseUrl = 'https://api.predis.ai/v1';
  
  Map<String, String> get _headers => {
    'Authorization': predisApiKey,
    'Accept': 'application/json',
  };

  static const String STATUS_PROCESSING = 'processing';
  static const String STATUS_COMPLETED = 'completed';
  static const String STATUS_FAILED = 'failed';

  // Generate video
  Future<Map<String, dynamic>> generateVideo({
    required String prompt,
    required BuildContext context,
  }) async {
    if (predisApiKey.isEmpty || predisBrandId.isEmpty) {
      NotificationService.showError(
        context: context,
        title: 'Configuration Error',
        message: 'API configuration is missing',
        errorType: ErrorType.apiNotFound,
        technicalDetails: 'Predis API key or Brand ID not found in environment variables',
      );
      throw VideoServiceException(
        VideoServiceError.apiKeyMissing,
        'API configuration missing',
        technicalDetails: 'Predis API key or Brand ID not found in environment variables',
      );
    }

    try {
      final Map<String, dynamic> requestBody = {
        'brand_id': predisBrandId,
        'text': prompt,
        'media_type': 'video',
        'video_duration': 'short',
        'input_language': 'english',
        'output_language': 'english',
        'post_type': 'generic',
        'webhook_url': webhookUrl,
      };

      print('Sending request to: $baseUrl/create_content/');
      print('Request body: $requestBody');

      final response = await http.post(
        Uri.parse('$baseUrl/create_content/'),
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        Duration(minutes: 2),
        onTimeout: () {
          NotificationService.showError(
            context: context,
            title: 'Request Timeout',
            message: 'The request took too long to complete. Please try again.',
            errorType: ErrorType.serviceError,
          );
          throw VideoServiceException(
            VideoServiceError.timeoutError,
            'Request timed out. Please try again.',
            technicalDetails: 'Generate video request timed out after 2 minutes',
          );
        },
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        NotificationService.showSuccess(
          context: context,
          title: 'Video Generation Started',
          message: 'Your video is being generated. This may take a few minutes.',
          playSound: true,
        );
        return {
          'post_id': responseData['post_ids']?[0] ?? responseData['post_id'],
          'status': responseData['post_status'] ?? 'processing',
        };
      } else {
        _handlePredisError(response.statusCode, jsonDecode(response.body), context);
      }
    } catch (e) {
      if (e is VideoServiceException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        NotificationService.showError(
          context: context,
          title: 'Network Error',
          message: 'Please check your internet connection and try again.',
          errorType: ErrorType.networkError,
        );
        throw VideoServiceException(
          VideoServiceError.networkError,
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
      NotificationService.showError(
        context: context,
        title: 'Unexpected Error',
        message: 'An unexpected error occurred. Please try again.',
        errorType: ErrorType.otherError,
        technicalDetails: e.toString(),
      );
      throw VideoServiceException(
        VideoServiceError.unknownError,
        'An unexpected error occurred',
        technicalDetails: e.toString(),
      );
    }

    throw VideoServiceException(
      VideoServiceError.unknownError,
      'Failed to generate video',
      technicalDetails: 'No response data available',
    );
  }

  // Get video status and details
  Future<Map<String, dynamic>> getVideoStatus(String postId, BuildContext context) async {
    try {
      final queryParams = {
        'brand_id': predisBrandId,
        'media_type': 'video',
        'webhook_url': webhookUrl,
      };

      final uri = Uri.parse('$baseUrl/get_posts/').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final posts = responseData['posts'] as List;
        final post = posts.firstWhere(
          (post) => post['post_id'] == postId,
          orElse: () => null,
        );

        if (post != null) {
          final videoUrl = post['generated_media']?[0]?['url'];
          final thumbUrl = post['generated_media']?[0]?['thumb_url'];
          final caption = post['caption'];
          
          if (post['status'] == STATUS_COMPLETED && videoUrl != null) {
            NotificationService.showSuccess(
              context: context,
              title: 'Video Generated',
              message: 'Your video is ready!',
              playSound: true,
            );
          }
          
          return {
            'status': post['status'],
            'video_url': videoUrl,
            'thumbnail_url': thumbUrl,
            'caption': caption,
          };
        }
      }
      
      return {'status': 'processing'};
    } catch (e) {
      print('Error getting video status: $e');
      return {'status': 'processing'};
    }
  }

  // Get list of videos
  Future<Map<String, dynamic>> listVideos({
    required BuildContext context,
    int page = 1,
    int limit = 10,
  }) async {
    if (predisApiKey.isEmpty || predisBrandId.isEmpty) {
      NotificationService.showError(
        context: context,
        title: 'Configuration Error',
        message: 'API configuration is missing',
        errorType: ErrorType.apiNotFound,
      );
      throw VideoServiceException(
        VideoServiceError.apiKeyMissing,
        'API configuration missing',
        technicalDetails: 'Predis API key or Brand ID not found in environment variables',
      );
    }

    try {
      final queryParams = {
        'brand_id': predisBrandId,
        'media_type': 'video',
        'page_n': page.toString(),
        'items_n': limit.toString(),
        'webhook_url': webhookUrl,
      };

      final uri = Uri.parse('$baseUrl/get_posts/').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
      ).timeout(
        Duration(seconds: 15),
        onTimeout: () {
          NotificationService.showError(
            context: context,
            title: 'Request Timeout',
            message: 'Failed to load videos. Please try again.',
            errorType: ErrorType.serviceError,
          );
          throw VideoServiceException(
            VideoServiceError.timeoutError,
            'Request timed out. Please try again.',
            technicalDetails: 'List videos request timed out after 15 seconds',
          );
        },
      );

      print('List videos response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final posts = responseData['posts'] as List;
        
        final formattedPosts = posts.map((post) {
          final videoUrl = post['generated_media']?[0]?['url'];
          final thumbUrl = post['generated_media']?[0]?['thumb_url'];
          final caption = post['caption'];
          
          return {
            'post_id': post['post_id'],
            'status': post['status'],
            'video_url': videoUrl,
            'thumbnail_url': thumbUrl,
            'caption': caption,
          };
        }).toList();

        return {
          'data': formattedPosts,
          'total_pages': responseData['total_pages'] ?? 1,
        };
      } else {
        final errorData = jsonDecode(response.body);
        _handlePredisError(response.statusCode, errorData, context);
      }
    } catch (e) {
      if (e is VideoServiceException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        NotificationService.showError(
          context: context,
          title: 'Network Error',
          message: 'Please check your internet connection and try again.',
          errorType: ErrorType.networkError,
        );
        throw VideoServiceException(
          VideoServiceError.networkError,
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
      NotificationService.showError(
        context: context,
        title: 'Error Loading Videos',
        message: 'An unexpected error occurred.',
        errorType: ErrorType.otherError,
        technicalDetails: e.toString(),
      );
      throw VideoServiceException(
        VideoServiceError.unknownError,
        'An unexpected error occurred',
        technicalDetails: e.toString(),
      );
    }

    throw VideoServiceException(
      VideoServiceError.unknownError,
      'Failed to list videos',
      technicalDetails: 'No response data available',
    );
  }

  // Download video to local storage with progress
  Future<File> downloadVideo(String downloadUrl, BuildContext context, {Function(double)? onProgress}) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request).timeout(
        Duration(minutes: 5),
        onTimeout: () {
          NotificationService.showError(
            context: context,
            title: 'Download Timeout',
            message: 'Video download took too long. Please try again.',
            errorType: ErrorType.serviceError,
          );
          throw VideoServiceException(
            VideoServiceError.timeoutError,
            'Download timed out. Please try again.',
            technicalDetails: 'Download request timed out after 5 minutes',
          );
        },
      );

      if (response.statusCode != 200) {
        NotificationService.showError(
          context: context,
          title: 'Download Failed',
          message: 'Unable to download video.',
          errorType: ErrorType.serviceError,
        );
        throw VideoServiceException(
          VideoServiceError.serverError,
          'Unable to download video',
          technicalDetails: 'Server responded with ${response.statusCode}',
        );
      }

      // Get the downloads directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        directory = Directory('${appDir.path}/Downloads');
      }

      // Create the directory if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/AI_Video_$timestamp.mp4');

      // Download with progress
      final totalBytes = response.contentLength ?? 0;
      var downloadedBytes = 0;
      final fileStream = file.openWrite();

      await response.stream.listen(
        (chunk) {
          downloadedBytes += chunk.length;
          if (totalBytes > 0 && onProgress != null) {
            onProgress(downloadedBytes / totalBytes);
          }
          fileStream.add(chunk);
        },
        onDone: () async {
          await fileStream.close();
          NotificationService.showSuccess(
            context: context,
            title: 'Download Complete',
            message: 'Video saved to Downloads folder',
            playSound: true,
          );
        },
        cancelOnError: true,
      ).asFuture();

      return file;
    } catch (e) {
      if (e is VideoServiceException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        NotificationService.showError(
          context: context,
          title: 'Network Error',
          message: 'Download failed due to network error.',
          errorType: ErrorType.networkError,
        );
        throw VideoServiceException(
          VideoServiceError.networkError,
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
      NotificationService.showError(
        context: context,
        title: 'Download Error',
        message: 'Failed to download video.',
        errorType: ErrorType.otherError,
        technicalDetails: e.toString(),
      );
      throw VideoServiceException(
        VideoServiceError.unknownError,
        'An unexpected error occurred',
        technicalDetails: e.toString(),
      );
    }
  }

  void _handlePredisError(int statusCode, Map<String, dynamic> errorData, BuildContext context) {
    print('Handling error - Status code: $statusCode');
    print('Error data: $errorData');
    
    final errors = errorData['errors'] as List?;
    final errorMessage = errors?.first['detail'] ?? 'Unknown error occurred';
    
    switch (statusCode) {
      case 429:
        final limits = errorData['API Limits'];
        if (limits != null) {
          final used = limits['api_request_in_last_one_hour'];
          final allowed = limits['total_requests_allowed_per_hour'];
          NotificationService.showError(
            context: context,
            title: 'Rate Limit Exceeded',
            message: 'Too many requests. Please try again later.',
            errorType: ErrorType.serviceError,
            technicalDetails: 'Used: $used, Allowed per hour: $allowed',
          );
          throw VideoServiceException(
            VideoServiceError.rateLimitExceeded,
            'Too many requests. Please try again later.',
            technicalDetails: 'Used: $used, Allowed per hour: $allowed',
          );
        } else {
          NotificationService.showError(
            context: context,
            title: 'Rate Limit Exceeded',
            message: 'Too many requests. Please try again later.',
            errorType: ErrorType.serviceError,
          );
          throw VideoServiceException(
            VideoServiceError.rateLimitExceeded,
            'Too many requests. Please try again later.',
            technicalDetails: errorMessage,
          );
        }
      case 400:
        if (errorMessage.contains('invalid brand_id')) {
          NotificationService.showError(
            context: context,
            title: 'Configuration Error',
            message: 'Invalid brand ID. Please contact support.',
            errorType: ErrorType.apiNotFound,
          );
          throw VideoServiceException(
            VideoServiceError.invalidBrandId,
            'Configuration error. Please contact support.',
            technicalDetails: errorMessage,
          );
        } else if (errorMessage.contains('reached your post generation limit')) {
          NotificationService.showError(
            context: context,
            title: 'Generation Limit Reached',
            message: 'You have reached your video generation limit.',
            errorType: ErrorType.serviceError,
          );
          throw VideoServiceException(
            VideoServiceError.generationLimitExceeded,
            'Video generation limit reached.',
            technicalDetails: errorMessage,
          );
        } else if (errorMessage.contains('3 posts inProgress')) {
          NotificationService.showError(
            context: context,
            title: 'Queue Full',
            message: 'Please wait for your current videos to complete.',
            errorType: ErrorType.serviceError,
          );
          throw VideoServiceException(
            VideoServiceError.maxQueueReached,
            'Please wait for current videos to complete.',
            technicalDetails: errorMessage,
          );
        }
        NotificationService.showError(
          context: context,
          title: 'Request Error',
          message: 'Unable to process request.',
          errorType: ErrorType.serviceError,
          technicalDetails: errorMessage,
        );
        throw VideoServiceException(
          VideoServiceError.serverError,
          'Unable to process request.',
          technicalDetails: errorMessage,
        );
      default:
        NotificationService.showError(
          context: context,
          title: 'Server Error',
          message: 'Unable to connect to server.',
          errorType: ErrorType.serviceError,
          technicalDetails: 'Status code: $statusCode, Message: $errorMessage',
        );
        throw VideoServiceException(
          VideoServiceError.serverError,
          'Unable to connect to server.',
          technicalDetails: 'Status code: $statusCode, Message: $errorMessage',
        );
    }
  }

  // Cancel video generation
  Future<void> cancelGeneration(String postId, BuildContext context) async {
    try {
      final Map<String, dynamic> requestBody = {
        'brand_id': predisBrandId,
        'post_id': postId,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/cancel_generation/'),
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        Duration(seconds: 15),
        onTimeout: () {
          NotificationService.showError(
            context: context,
            title: 'Request Timeout',
            message: 'Failed to cancel generation. Please try again.',
            errorType: ErrorType.serviceError,
          );
          throw VideoServiceException(
            VideoServiceError.timeoutError,
            'Request timed out. Please try again.',
            technicalDetails: 'Cancel generation request timed out after 15 seconds',
          );
        },
      );

      if (response.statusCode == 200) {
        NotificationService.showSuccess(
          context: context,
          title: 'Generation Cancelled',
          message: 'Video generation has been cancelled.',
        );
      } else {
        _handlePredisError(response.statusCode, jsonDecode(response.body), context);
      }
    } catch (e) {
      if (e is VideoServiceException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        NotificationService.showError(
          context: context,
          title: 'Network Error',
          message: 'Please check your internet connection and try again.',
          errorType: ErrorType.networkError,
        );
        throw VideoServiceException(
          VideoServiceError.networkError,
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
      NotificationService.showError(
        context: context,
        title: 'Cancel Error',
        message: 'Failed to cancel video generation.',
        errorType: ErrorType.otherError,
        technicalDetails: e.toString(),
      );
      throw VideoServiceException(
        VideoServiceError.unknownError,
        'An unexpected error occurred',
        technicalDetails: e.toString(),
      );
    }
  }
} 