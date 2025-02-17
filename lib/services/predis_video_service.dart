import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/ai_service_config.dart';
import '../models/generation_request.dart';
import '../models/generation_type.dart';
import 'notification_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'token_service.dart';

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
  static const Duration requestTimeout = Duration(minutes: 5);
  static const int maxRetries = 3;
  static const Duration queueCleanupInterval = Duration(hours: 24);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AIServiceConfig _config;
  bool _isInitialized = false;
  
  // Rate limiting constants
  static const int _maxRequestsPerMinute = 60;  // Global Predis API limit per key
  static const int _maxTemplateRequestsPerMinute = 10;
  static const Duration _rateLimitWindow = Duration(minutes: 1);
  
  // Queue management constants
  static const int maxConcurrentRequests = 40;
  static const Duration queueTimeout = Duration(minutes: 1);  // Changed to 1 minute
  
  final FirebaseStorage _storage = FirebaseStorage.instance;

  PredisVideoService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required AIServiceConfig config,
  })  : _firestore = firestore,
        _auth = auth,
        _config = config {
    _init();
  }

  Future<void> _init() async {
    if (!_isInitialized) {
      debugPrint('[PredisVideo] Initializing service');
      await dotenv.load(fileName: ".env");  // Ensure .env is loaded
      await _validateConfig();
      _startQueueCleaner();
      debugPrint('[PredisVideo] Service initialized: $_isInitialized');
    }
  }

  Future<void> _validateConfig() async {
    final apiKey = _config.apiKey;
    final brandId = _config.defaultParams['brand_id'];
    
    debugPrint('[PredisVideo] Validating config - API Key: ${apiKey.isEmpty ? 'empty' : 'present'}, Brand ID: ${brandId?.isEmpty ?? true ? 'empty' : 'present'}');
    
    if (apiKey.isEmpty) {
      debugPrint('[PredisVideo] WARNING: Predis API key is not set in config');
      _isInitialized = false;
      return;
    }
    if (brandId == null || brandId.isEmpty) {
      debugPrint('[PredisVideo] WARNING: Predis Brand ID is not set in config');
      _isInitialized = false;
      return;
    }
    
    _isInitialized = true;
    debugPrint('[PredisVideo] Configuration validated successfully');
  }

  Future<bool> _ensureInitialized() async {
    if (!_isInitialized) {
      await _init();
    }
    return _isInitialized;
  }

  Future<bool> _checkRateLimit() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final now = DateTime.now();
      final oneMinuteAgo = now.subtract(const Duration(minutes: 1));

      final requests = await _firestore
          .collection('api_requests')
          .where('type', isEqualTo: 'video')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(oneMinuteAgo))
          .get();

      return requests.size < _maxRequestsPerMinute;
    } catch (e) {
      debugPrint('Error checking rate limit: $e');
      return false;
    }
  }

  Future<void> _recordApiRequest(String type) async {
    try {
      await _firestore.collection('api_requests').add({
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error recording API request: $e');
    }
  }

  Future<void> _cleanupQueue() async {
    try {
      debugPrint('[PredisVideo] Starting queue cleanup');
      final user = _auth.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final batch = _firestore.batch();

      // Find all requests older than 1 minute
      final oldRequests = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: [
            GenerationStatus.queued.value,
            GenerationStatus.processing.value,
            GenerationStatus.pending.value,
          ])
          .where('updatedAt', isLessThan: Timestamp.fromDate(now.subtract(queueTimeout)))
          .get();

      debugPrint('[PredisVideo] Found ${oldRequests.docs.length} old requests to cleanup');

      for (final doc in oldRequests.docs) {
        final request = GenerationRequest.fromMap(doc.data());
        
        // Archive the request
        await _firestore.collection('generation_history').add({
          ...doc.data(),
          'status': GenerationStatus.failed.value,
          'error': 'Request expired after ${queueTimeout.inMinutes} minute',
          'archivedAt': FieldValue.serverTimestamp(),
        });

        // Delete from active queue
        batch.delete(doc.reference);
      }

      await batch.commit();
      debugPrint('[PredisVideo] Queue cleanup completed');
    } catch (e, stack) {
      debugPrint('[PredisVideo] Queue cleanup error: $e\n$stack');
    }
  }

  Future<int> _getQueuePosition(String requestId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 0;

      // Get only active requests in queue ordered by creation time (newest first)
      final queueSnapshot = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: GenerationStatus.queued.value)
          .orderBy('createdAt', descending: true)  // LIFO order
          .orderBy('__name__')
          .get();
      
      final position = queueSnapshot.docs
          .indexWhere((doc) => doc.id == requestId);
      
      debugPrint('[PredisVideo] Queue position for $requestId: ${position >= 0 ? position + 1 : 0}');
      return position >= 0 ? position + 1 : 0;
    } catch (e, stack) {
      debugPrint('[PredisVideo] Error getting queue position: $e\n$stack');
      return 0;
    }
  }

  Future<void> _processQueue() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      debugPrint('[PredisVideo] Processing queue...');
      
      final snapshot = await _firestore
          .collection('generation_queue')
          .where('status', isEqualTo: GenerationStatus.pending.value)
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: false)
          .limit(5)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('[PredisVideo] No pending requests in queue');
        return;
      }

      // Process requests
      for (final doc in snapshot.docs) {
        final request = GenerationRequest.fromMap(doc.data());
        try {
          debugPrint('[PredisVideo] Processing request: ${request.id}');
          
          // Update status to processing
          await _firestore.collection('generation_queue').doc(doc.id).update({
            'status': GenerationStatus.processing.value,
            'startedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Make API request
          final response = await _makeApiRequest(request);
          
          // Store video information
          final videoInfo = await _storeVideoInformation(
            userId: request.userId,
            videoUrl: response['outputUrl'],
            prompt: request.prompt,
            requestId: request.id,
            metadata: request.metadata ?? {},
          );

          // Update request with success
          await _firestore.collection('generation_queue').doc(doc.id).update({
            'status': GenerationStatus.completed.value,
            'result': videoInfo['downloadUrl'],
            'thumbnailUrl': videoInfo['thumbnailUrl'],
            'videoId': videoInfo['videoId'],
            'filename': videoInfo['filename'],
            'postIds': response['post_ids'],
            'progress': 100,
            'completedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Record API request
          await _recordApiRequest('video');
          
          debugPrint('[PredisVideo] Successfully processed request: ${request.id}');
        } catch (e) {
          debugPrint('[PredisVideo] Error processing request ${doc.id}: $e');
          await _handleError(doc.id, e);
        }
      }
    } catch (e) {
      debugPrint('[PredisVideo] Error processing queue: $e');
    }
  }

  Future<void> _processRequest(GenerationRequest request) async {
    try {
      if (!await _checkRateLimit()) {
        throw Exception('Rate limit exceeded. Please try again later.');
      }

      await _firestore.collection('generation_queue').doc(request.id).update({
        'status': GenerationStatus.processing.value,
        'progress': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final response = await _makeApiRequest(request);
      
      // Store video information
      final videoInfo = await _storeVideoInformation(
        userId: request.userId,
        videoUrl: response['outputUrl'],
        prompt: request.prompt,
        requestId: request.id,
        metadata: request.metadata ?? {},
      );

      // Update request with success
      await _firestore.collection('generation_queue').doc(request.id).update({
        'status': GenerationStatus.completed.value,
        'result': videoInfo['downloadUrl'],
        'thumbnailUrl': videoInfo['thumbnailUrl'],
        'videoId': videoInfo['videoId'],
        'filename': videoInfo['filename'],
        'postIds': response['post_ids'],
        'progress': 100,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _recordApiRequest('video');
    } catch (e) {
      debugPrint('[PredisVideo] Error processing request: $e');
      await _handleError(request.id, e);
      rethrow;
    }
  }

  Future<String?> submitRequest(String prompt, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Check token balance first
      final tokenCost = GenerationType.video.defaultTokenCost;
      final tokenService = TokenService(_firestore, _auth);
      await tokenService.checkTokenBalance(tokenCost);

      // Cleanup old requests first
      await _cleanupQueue();

      // Create request document
      final requestRef = _firestore.collection('generation_queue').doc();
      final Map<String, dynamic> baseMetadata = {
        'prompt': prompt,
        'content_type': 'video',
        'media_type': 'video',
        'brand_id': _config.defaultParams['brand_id'],
        'input_language': 'english',
        'output_language': 'english',
        'video_type': 'short',
        'duration': '30',
        'api_key': _config.apiKey,
        'retryCount': 0,
        'attempts': 0,
        'maxAttempts': 3,
        'priority': 1,
        'tokenCost': tokenCost,
      };

      final request = GenerationRequest(
        id: requestRef.id,
        userId: user.uid,
        type: GenerationType.video,
        prompt: prompt,
        status: 'queued',
        timestamp: DateTime.now(),
        tokenCost: tokenCost,
        progress: 0,
        metadata: baseMetadata,
      );

      await requestRef.set(request.toMap());
      debugPrint('[PredisVideo] Created new request: ${requestRef.id}');
      
      // Start queue processing
      _processQueue();
      
      return requestRef.id;
    } catch (e, stack) {
      debugPrint('[PredisVideo] Error submitting request: $e\n$stack');
      rethrow;
    }
  }

  Future<int> _getActiveRequestsCount(String userId) async {
    final snapshot = await _firestore
        .collection('generation_queue')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: [
          GenerationStatus.pending.value,
          GenerationStatus.processing.value,
        ])
        .get();

    return snapshot.docs.length;
  }

  Future<List<GenerationRequest>> getRecentVideos({
    required BuildContext context,
    int limit = 5,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      debugPrint('[PredisVideo] Fetching recent videos for user: ${user.uid}');

      // Get from Firestore with cache
      final snapshot = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: GenerationType.video.toString().split('.').last)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get(GetOptions(source: Source.serverAndCache));

      final requests = snapshot.docs
          .map((doc) => GenerationRequest.fromMap(doc.data()))
          .toList();

      debugPrint('[PredisVideo] Found ${requests.length} recent videos in Firestore');
      return requests;
    } catch (e, stack) {
      debugPrint('[PredisVideo] Error fetching recent videos: $e\n$stack');
      NotificationService.showError(
        context: context,
        title: 'Error',
        message: 'Failed to fetch recent videos',
        technicalDetails: e.toString(),
      );
      return [];
    }
  }

  Future<String?> generateVideo(String prompt, Map<String, dynamic> metadata) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Authentication required');
      }

      // Check rate limits
      if (!await _checkRateLimit()) {
        throw Exception('Rate limit exceeded. Please try again later.');
      }

      // Create request document
      final requestId = _firestore.collection('generation_queue').doc().id;
      debugPrint('[PredisVideo] Creating request: $requestId');

      final request = GenerationRequest(
        id: requestId,
        userId: user.uid,
        type: GenerationType.video,
        prompt: prompt,
        status: GenerationStatus.pending.value,
        timestamp: DateTime.now(),
        tokenCost: GenerationType.video.defaultTokenCost,
        metadata: {
          ...metadata,
          'serviceType': 'video',
          'provider': 'predis',
        },
      );

      try {
        await _firestore
            .collection('generation_queue')
            .doc(requestId)
            .set(request.toJson());
        
        // Start queue processing
        _processQueue();
        
        return requestId;
      } catch (e) {
        debugPrint('[PredisVideo] Generation error: $e');
        throw Exception('Failed to start video generation: ${e.toString()}');
      }
    } catch (e) {
      debugPrint('[PredisVideo] Generation error: $e');
      throw Exception('Failed to generate video: ${e.toString()}');
    }
  }

  void _listenToRequestStatus(String requestId, BuildContext context) {
    debugPrint('[PredisVideo] Starting to listen to request: $requestId');
    _firestore
        .collection('generation_queue')
        .doc(requestId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        debugPrint('[PredisVideo] Request no longer exists: $requestId');
        return;
      }

      final request = GenerationRequest.fromMap(snapshot.data()!);
      debugPrint('[PredisVideo] Request status update: ${request.status} (${request.progress}%)');
      
      switch (request.status) {
        case 'completed':
          // Deduct tokens only on successful completion
          await _firestore.collection('users').doc(request.userId).update({
            'tokens': FieldValue.increment(-request.tokenCost),
          });
          break;
        case 'failed':
          final errorMessage = request.errorMessage;
          debugPrint('[PredisVideo] Generation failed: $errorMessage');
          break;
      }
    });
  }

  Future<void> _refundTokens(String userId, int amount) async {
    await _firestore.collection('users').doc(userId).update({
      'tokens': FieldValue.increment(amount),
    });
  }

  Future<void> cancelRequest(String requestId, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final requestRef = _firestore.collection('generation_queue').doc(requestId);
      final request = await requestRef.get();

      if (!request.exists) throw Exception('Request not found');
      if (request.data()!['userId'] != user.uid) throw Exception('Not authorized');

      // Only allow cancellation for queued or pending requests
      final status = request.data()!['status'];
      if (status != GenerationStatus.queued.value && 
          status != GenerationStatus.pending.value) {
        throw Exception('Cannot cancel request in current state');
      }

      await requestRef.update({
        'status': GenerationStatus.cancelled.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Refund tokens
      final tokensUsed = request.data()!['tokensUsed'] as int;
      await _firestore.collection('users').doc(user.uid).update({
        'tokens': FieldValue.increment(tokensUsed),
      });
    } catch (e) {
      debugPrint('[PredisVideo] Cancel error: $e');
      rethrow;
    }
  }

  Future<void> retryRequest(String requestId, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final requestRef = _firestore.collection('generation_queue').doc(requestId);
      final request = await requestRef.get();

      if (!request.exists) throw Exception('Request not found');
      if (request.data()!['userId'] != user.uid) throw Exception('Not authorized');

      // Check retry count
      final retryCount = request.data()!['retryCount'] as int;
      if (retryCount >= 3) {
        throw Exception('Maximum retry attempts reached');
      }

      // Reset request status
      await requestRef.update({
        'status': GenerationStatus.queued.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'retryCount': FieldValue.increment(1),
        'attempts': 0,
        'progress': 0,
        'error': null,
      });
    } catch (e) {
      debugPrint('[PredisVideo] Retry error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _makeApiRequest(GenerationRequest request) async {
    if (!await _ensureInitialized()) {
      debugPrint('[PredisVideo] Service not initialized. API Key: ${_config.apiKey.isEmpty ? 'empty' : 'present'}, Brand ID: ${_config.defaultParams['brand_id']?.isEmpty ?? true ? 'empty' : 'present'}');
      throw Exception('Service not initialized. Please check your API configuration.');
    }

    try {
      final apiKey = _config.apiKey;
      final brandId = _config.defaultParams['brand_id'];

      debugPrint('[PredisVideo] Making request with API Key: ${apiKey.isEmpty ? 'empty' : 'present'}, Brand ID: ${brandId?.isEmpty ?? true ? 'empty' : 'present'}');

      if (apiKey.isEmpty || brandId == null || brandId.isEmpty) {
        throw Exception('API configuration missing. Please check your environment variables.');
      }

      debugPrint('[PredisVideo] Making API request for request: ${request.id}');

      // Create multipart request
      final uri = Uri.parse('https://brain.predis.ai/predis_api/v1/create_content/');
      final httpRequest = http.MultipartRequest('POST', uri);

      // Add headers
      httpRequest.headers.addAll({
        'Authorization': apiKey.startsWith('Bearer ') ? apiKey : 'Bearer $apiKey',
        'Accept': 'application/json',
      });

      // Add form fields with optimized settings for shorter videos and lower credit usage
      httpRequest.fields.addAll({
        'brand_id': brandId,
        'text': request.prompt,
        'media_type': 'video',
        'video_duration': 'short',  // Changed from 'long' to 'short'
        'video_type': 'short_form', // Added to specify short-form content
        'duration': '15',           // Set to 15 seconds for optimal credit usage
        'quality': 'standard',      // Use standard quality instead of high
        'input_language': 'english',
        'output_language': 'english',
        'color_palette_type': 'ai_suggested',
        'optimize_credits': 'true', // Added to request credit optimization
      });

      debugPrint('[PredisVideo] Sending request with fields: ${httpRequest.fields}');

      // Send request
      final streamedResponse = await httpRequest.send().timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw Exception('Request timed out');
        },
      );

      // Get response
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('[PredisVideo] Response status: ${response.statusCode}');
      debugPrint('[PredisVideo] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['errors'] != null && (data['errors'] as List).isNotEmpty) {
          final error = data['errors'][0];
          throw Exception('API Error: ${error['detail']} - ${error['solution']}');
        }

        final postId = data['post_ids']?[0];
        if (postId == null) {
          throw Exception('No post ID returned from API');
        }

        // Start polling for video status
        final videoData = await _pollForVideoStatus(postId, brandId, apiKey);
        
        // Return response data without saving to Firebase
        return {
          'outputUrl': videoData['video_url'] ?? '',
          'post_ids': [postId],
          'status': videoData['status'] ?? 'completed',
          'thumbnailUrl': videoData['thumbnail_url'],
        };
      } else if (response.statusCode == 429) {
        throw Exception('Rate limit exceeded. Please try again later.');
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['message'] ?? 'Unknown error occurred';
        throw Exception('API Error: $errorMessage');
      }
    } catch (e) {
      debugPrint('[PredisVideo] API request error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _pollForVideoStatus(String postId, String brandId, String apiKey) async {
    debugPrint('[PredisVideo] Starting to poll for video status: $postId');
    int attempts = 0;
    const maxAttempts = 30; // 5 minutes with 10-second intervals
    
    while (attempts < maxAttempts) {
      try {
        final uri = Uri.parse('https://brain.predis.ai/predis_api/v1/get_posts/').replace(
          queryParameters: {
            'brand_id': brandId,
            'post_id': postId,
          },
        );

        final response = await http.get(
          uri,
          headers: {
            'Authorization': apiKey.startsWith('Bearer ') ? apiKey : 'Bearer $apiKey',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final posts = data['posts'] as List;
          
          if (posts.isNotEmpty) {
            final post = posts[0];
            final status = post['status'];
            final videoUrl = post['generated_media']?[0]?['url'];
            final thumbnailUrl = post['generated_media']?[0]?['thumb_url'];
            
            debugPrint('[PredisVideo] Poll status: $status, Video URL: ${videoUrl ?? 'not ready'}');
            
            if (status == 'completed' && videoUrl != null) {
              return {
                'status': 'completed',
                'video_url': videoUrl,
                'thumbnail_url': thumbnailUrl,
              };
            } else if (status == 'failed') {
              throw Exception('Video generation failed');
            }
          }
        }
        
        attempts++;
        await Future.delayed(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('[PredisVideo] Error polling for video status: $e');
        rethrow;
      }
    }
    
    throw Exception('Video generation timed out after ${maxAttempts * 10} seconds');
  }

  Future<void> _handleError(String requestId, dynamic error) async {
    try {
      String errorMessage = error.toString();
      String status = GenerationStatus.failed.value;

      // Parse error message
      if (error is Exception) {
        if (errorMessage.contains('API Error: 401')) {
          errorMessage = 'Authentication failed. Please check your API key.';
        } else if (errorMessage.contains('Rate limit exceeded')) {
          errorMessage = 'Rate limit exceeded. Please try again later.';
          status = GenerationStatus.pending.value; // Retry later
        } else if (errorMessage.contains('Request timed out')) {
          errorMessage = 'Request timed out. Please try again.';
          status = GenerationStatus.pending.value; // Retry later
        }
      }

      debugPrint('[PredisVideo] Handling error for request $requestId: $errorMessage');

      // Update request status
      await _firestore.collection('generation_queue').doc(requestId).update({
        'status': status,
        'error': {
          'message': errorMessage,
          'timestamp': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // If it's a permanent failure, refund tokens
      if (status == GenerationStatus.failed.value) {
        final request = await _firestore.collection('generation_queue').doc(requestId).get();
        if (request.exists) {
          final tokenCost = request.data()?['tokenCost'] ?? 0;
          if (tokenCost > 0) {
            await _refundTokens(request.data()!['userId'], tokenCost);
          }
        }
      }
    } catch (e) {
      debugPrint('[PredisVideo] Error handling failure: $e');
    }
  }

  Map<String, dynamic> _getRequestData(String requestId, Map<String, dynamic>? params) {
    final Map<String, dynamic> baseMetadata = {
      'content_type': 'video',
      'media_type': 'video',
      'brand_id': _config.defaultParams['brand_id'],
      'input_language': 'english',
      'output_language': 'english',
      'video_type': 'short_form',
      'duration': '15',
      'quality': 'standard',
      'optimize_credits': 'true',
      'api_key': _config.apiKey,
    };

    if (params != null) {
      baseMetadata.addAll(params);
    }

    return {
      'id': requestId,
      'type': 'video',
      'metadata': baseMetadata,
    };
  }

  Future<void> _startQueueCleaner() async {
    Timer.periodic(queueCleanupInterval, (_) => _cleanupQueue());
  }

  Future<Map<String, dynamic>> _storeVideoInformation({
    required String userId,
    required String videoUrl,
    required String prompt,
    required String requestId,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      // Generate a unique filename
      final filename = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      // Store video information in Firestore without uploading to Firebase Storage
      final videoDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_videos')
          .add({
        'filename': filename,
        'originalUrl': videoUrl,
        'downloadUrl': videoUrl, // Use original URL directly
        'prompt': prompt,
        'requestId': requestId,
        'metadata': metadata,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'size': 0, // Will be updated when actually downloaded
        'duration': metadata['duration'] ?? '30',
        'isDownloaded': false,
        'isAddedToCollection': false,
        'thumbnailUrl': '', // Will be updated when added to collection
      });

      return {
        'videoId': videoDoc.id,
        'downloadUrl': videoUrl,
        'thumbnailUrl': '',
        'filename': filename,
      };
    } catch (e) {
      debugPrint('[PredisVideo] Error storing video info: $e');
      rethrow;
    }
  }

  Future<String> _generateThumbnail(String videoUrl, String userId, String videoId) async {
    try {
      // Generate thumbnail using video_thumbnail package or similar
      // For now, we'll just use a placeholder
      final thumbnailPath = 'users/$userId/thumbnails/thumb_$videoId.jpg';
      final thumbnailRef = _storage.ref().child(thumbnailPath);
      
      // TODO: Implement actual thumbnail generation
      // For now, store a placeholder
      final placeholder = Uint8List.fromList([]);
      await thumbnailRef.putData(placeholder, SettableMetadata(contentType: 'image/jpeg'));
      
      return await thumbnailRef.getDownloadURL();
    } catch (e) {
      debugPrint('[PredisVideo] Error generating thumbnail: $e');
      return '';
    }
  }

  Future<void> markVideoAsDownloaded(String videoId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('generated_videos')
          .doc(videoId)
          .update({
        'isDownloaded': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[PredisVideo] Error marking video as downloaded: $e');
      rethrow;
    }
  }

  Future<void> regenerateVideo(String videoId, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get original video data
      final videoDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('generated_videos')
          .doc(videoId)
          .get();

      if (!videoDoc.exists) throw Exception('Video not found');

      final videoData = videoDoc.data()!;
      
      // Create new generation request with same prompt
      final requestId = await submitRequest(
        videoData['prompt'],
        context,
      );

      if (requestId != null) {
        NotificationService.showSuccess(
          context: context,
          title: 'Regeneration Started',
          message: 'Your video is being regenerated',
        );
      }
    } catch (e) {
      debugPrint('[PredisVideo] Error regenerating video: $e');
      NotificationService.showError(
        context: context,
        title: 'Regeneration Failed',
        message: 'Failed to regenerate video',
        technicalDetails: e.toString(),
      );
    }
  }

  Future<void> _updateRequestStatus(String requestId, String status, {
    String? errorMessage,
    Map<String, dynamic>? result,
    double? progress,
  }) async {
    final requestRef = _firestore.collection('generation_queue').doc(requestId);
    final request = await requestRef.get();
    
    if (!request.exists) return;
    
    final updates = {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (result != null) 'result': result,
      if (progress != null) 'progress': progress,
    };

    await requestRef.update(updates);

    // If the request is completed successfully, deduct tokens
    if (status == 'completed') {
      final data = request.data()!;
      final userId = data['userId'] as String;
      final tokenCost = data['tokenCost'] as int;
      final prompt = data['prompt'] as String;
      
      final tokenService = TokenService(_firestore, _auth);
      await tokenService.deductTokens(
        tokenCost,
        'Video Generation',
        prompt: prompt,
        outputUrl: result?['video_url'] ?? '',
        generatedFileName: result?['filename'] ?? '',
        serviceSpecificData: data['metadata'] as Map<String, dynamic>?,
      );

      // Update usage history
      await _firestore.collection('users').doc(userId).collection('usage_history').add({
        'type': 'video_generation',
        'timestamp': FieldValue.serverTimestamp(),
        'tokenCost': tokenCost,
        'prompt': prompt,
        'result': result,
        'requestId': requestId,
      });
    }
  }

  Future<void> addToCollection(String requestId, String videoUrl, String prompt, Map<String, dynamic> metadata) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      // Add to user's generated_videos collection instead of video_collection
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('generated_videos')
          .doc(requestId)
          .set({
        'videoUrl': videoUrl,
        'prompt': prompt,
        'metadata': metadata,
        'createdAt': FieldValue.serverTimestamp(),
        'userId': user.uid,
      });

      // Update the request to mark it as added to collection
      await _firestore
          .collection('generation_queue')
          .doc(requestId)
          .update({
        'addedToCollection': true,
      });

      debugPrint('[PredisVideo] Successfully added to collection: $requestId');
    } catch (e) {
      debugPrint('[PredisVideo] Error adding to collection: $e');
      throw Exception('Failed to add video to collection: $e');
    }
  }

  Future<void> removeFromCollection(String requestId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      // Remove from user's generated_videos collection
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('generated_videos')
          .doc(requestId)
          .delete();

      // Update the request to mark it as removed from collection
      await _firestore
          .collection('generation_queue')
          .doc(requestId)
          .update({
        'addedToCollection': false,
      });

      debugPrint('[PredisVideo] Successfully removed from collection: $requestId');
    } catch (e) {
      debugPrint('[PredisVideo] Error removing from collection: $e');
      throw Exception('Failed to remove video from collection: $e');
    }
  }
} 