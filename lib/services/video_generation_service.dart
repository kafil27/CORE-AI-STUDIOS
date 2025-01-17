import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  }) async {
    if (predisApiKey.isEmpty || predisBrandId.isEmpty) {
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
        return {
          'post_id': responseData['post_ids']?[0] ?? responseData['post_id'],
          'status': responseData['post_status'] ?? 'processing',
        };
      } else {
        _handlePredisError(response.statusCode, jsonDecode(response.body));
      }
    } catch (e) {
      if (e is VideoServiceException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        throw VideoServiceException(
          VideoServiceError.networkError,
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
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
  Future<Map<String, dynamic>> getVideoStatus(String postId) async {
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
  Future<Map<String, dynamic>> listVideos({int page = 1, int limit = 10}) async {
    if (predisApiKey.isEmpty || predisBrandId.isEmpty) {
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
        _handlePredisError(response.statusCode, errorData);
      }
    } catch (e) {
      if (e is VideoServiceException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        throw VideoServiceException(
          VideoServiceError.networkError,
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
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
  Future<File> downloadVideo(String downloadUrl, {Function(double)? onProgress}) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request).timeout(
        Duration(minutes: 5),
        onTimeout: () {
          throw VideoServiceException(
            VideoServiceError.timeoutError,
            'Download timed out. Please try again.',
            technicalDetails: 'Download request timed out after 5 minutes',
          );
        },
      );

      if (response.statusCode != 200) {
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
        },
        cancelOnError: true,
      ).asFuture(); // Convert StreamSubscription to Future

      return file;
    } catch (e) {
      if (e is VideoServiceException) rethrow;
      
      if (e.toString().contains('SocketException')) {
        throw VideoServiceException(
          VideoServiceError.networkError,
          'Network connection error',
          technicalDetails: 'Socket Exception: $e',
        );
      }
      
      throw VideoServiceException(
        VideoServiceError.unknownError,
        'An unexpected error occurred',
        technicalDetails: e.toString(),
      );
    }
  }

  void _handlePredisError(int statusCode, Map<String, dynamic> errorData) {
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
          throw VideoServiceException(
            VideoServiceError.rateLimitExceeded,
            'Too many requests. Please try again later.',
            technicalDetails: 'Used: $used, Allowed per hour: $allowed',
          );
        } else {
          throw VideoServiceException(
            VideoServiceError.rateLimitExceeded,
            'Too many requests. Please try again later.',
            technicalDetails: errorMessage,
          );
        }
      case 400:
        if (errorMessage.contains('invalid brand_id')) {
          throw VideoServiceException(
            VideoServiceError.invalidBrandId,
            'Configuration error. Please contact support.',
            technicalDetails: errorMessage,
          );
        } else if (errorMessage.contains('reached your post generation limit')) {
          throw VideoServiceException(
            VideoServiceError.generationLimitExceeded,
            'Video generation limit reached.',
            technicalDetails: errorMessage,
          );
        } else if (errorMessage.contains('3 posts inProgress')) {
          throw VideoServiceException(
            VideoServiceError.maxQueueReached,
            'Please wait for current videos to complete.',
            technicalDetails: errorMessage,
          );
        }
        throw VideoServiceException(
          VideoServiceError.serverError,
          'Unable to process request.',
          technicalDetails: errorMessage,
        );
      default:
        throw VideoServiceException(
          VideoServiceError.serverError,
          'Unable to connect to server.',
          technicalDetails: 'Status code: $statusCode, Message: $errorMessage',
        );
    }
  }

  Future<void> cancelGeneration(String postId) async {
    try {
      final response = await http.delete(
        Uri.parse('$predisBaseUrl/posts/$postId'),
        headers: {
          'Authorization': 'Bearer $predisApiKey',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw VideoServiceException(
          VideoServiceError.serverError,
          'Failed to cancel video generation',
          technicalDetails: 'Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw VideoServiceException(
        VideoServiceError.networkError,
        'Failed to cancel video generation',
        technicalDetails: e.toString(),
      );
    }
  }
} 