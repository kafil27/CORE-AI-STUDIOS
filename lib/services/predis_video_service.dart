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
      _isInitialized = true;
      _startQueueCleaner();
    }
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

  Future<bool> _checkRateLimit(String type) async {
    try {
      final now = DateTime.now();
      final oneMinuteAgo = now.subtract(Duration(minutes: 1));

      final snapshot = await _firestore
          .collection('api_requests')
          .where('type', isEqualTo: type)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(oneMinuteAgo))
          .get();

      return snapshot.docs.length < 60; // Allow 60 requests per minute
    } catch (e) {
      print('Error checking rate limit: $e');
      return true; // Allow request if rate limit check fails
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
      final snapshot = await _firestore
          .collection('generation_queue')
          .where('status', isEqualTo: 'pending')
          .orderBy('timestamp', descending: false)
          .limit(5)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('[PredisVideo] No pending requests in queue');
        return;
      }

      // Process requests concurrently
      await Future.wait(
        snapshot.docs.map((doc) async {
          final request = GenerationRequest.fromMap(doc.data());
          
          try {
            await _firestore.collection('generation_queue').doc(doc.id).update({
              'status': 'processing',
              'startedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            await _processRequest(request);

            await _firestore.collection('generation_queue').doc(doc.id).update({
              'status': 'completed',
              'completedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } catch (e) {
            debugPrint('[PredisVideo] Error processing request ${doc.id}: $e');
            await _handleError(doc.id, e);
          }
        }),
      );
    } catch (e, stack) {
      debugPrint('[PredisVideo] Error processing queue: $e\n$stack');
    }
  }

  Future<void> _processRequest(GenerationRequest request) async {
    try {
      // Check rate limit before processing
      if (!await _checkRateLimit('video')) {
        throw Exception('Rate limit exceeded. Please try again later.');
      }

      // Make the API request
      final response = await _makeApiRequest(request);
      
      // Update request with success
      await _firestore.collection('generation_queue').doc(request.id).update({
        'status': GenerationStatus.completed.value,
        'result': response['video_url'],
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Record API request
      await _recordApiRequest('video');
    } catch (e) {
      await _handleError(request.id, e);
      rethrow;
    }
  }

  Future<String?> submitRequest(String prompt, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

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
      };

      final request = GenerationRequest(
        id: requestRef.id,
        userId: user.uid,
        type: GenerationType.video,
        prompt: prompt,
        status: 'queued',
        timestamp: DateTime.now(),
        tokenCost: 100,
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

  Future<String?> generateVideo({
    required BuildContext context,
    required String prompt,
    Map<String, dynamic>? additionalParams,
  }) async {
    debugPrint('[PredisVideo] Starting video generation with prompt: $prompt');
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
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Cleanup queue first
      await _cleanupQueue();

      // Check user's token balance
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      
      final tokens = userDoc.data()?['tokens'] as int? ?? 0;
      debugPrint('[PredisVideo] User token balance: $tokens');
      if (tokens < 100) {
        NotificationService.showError(
          context: context,
          title: 'Insufficient Tokens',
          message: 'You need at least 100 tokens to generate a video',
        );
        return null;
      }

      // Check rate limits
      if (!await _checkRateLimit('video')) {
        NotificationService.showError(
          context: context,
          title: 'Rate Limit',
          message: 'The service is currently busy. Please try again in a minute.',
        );
        return null;
      }

      // Create generation request
      final requestRef = _firestore.collection('generation_queue').doc();
      debugPrint('[PredisVideo] Creating request: ${requestRef.id}');
      
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
      };

      if (additionalParams != null) {
        baseMetadata.addAll(additionalParams);
      }

      final request = GenerationRequest(
        id: requestRef.id,
        userId: user.uid,
        type: GenerationType.video,
        prompt: prompt,
        status: 'queued',
        timestamp: DateTime.now(),
        tokenCost: 100,
        progress: 0,
        metadata: baseMetadata,
      );

      // Save request without deducting tokens yet
      await requestRef.set(request.toMap());
      
      debugPrint('[PredisVideo] Starting status listener');
      _listenToRequestStatus(requestRef.id, context);

      // Record API request for rate limiting
      await _recordApiRequest('video');

      // Start queue processing
      _processQueue();

      return requestRef.id;
    } catch (e, stack) {
      debugPrint('[PredisVideo] Generation error: $e\n$stack');
      NotificationService.showError(
        context: context,
        title: 'Generation Error',
        message: 'Failed to start video generation',
        technicalDetails: e.toString(),
      );
      return null;
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
          NotificationService.showSuccess(
            context: context,
            title: 'Video Generated',
            message: 'Your video has been generated successfully',
            playSound: true,
          );
          break;
        case 'failed':
          final errorMessage = request.errorMessage;
          debugPrint('[PredisVideo] Generation failed: $errorMessage');
          if (errorMessage != null && errorMessage.toLowerCase().contains('rate limit')) {
            NotificationService.showError(
              context: context,
              title: 'Rate Limit Exceeded',
              message: 'Your request will be retried automatically',
              showPopup: true,
            );
          } else {
            NotificationService.showError(
              context: context,
              title: 'Generation Failed',
              message: request.errorMessage ?? 'Failed to generate video',
              showPopup: true,
            );
          }
          break;
        case 'queued':
          if (request.status == 'queued') {
            _getQueuePosition(requestId).then((position) {
              if (position > 1) {
                NotificationService.showInfo(
                  context: context,
                  title: 'Queue Update',
                  message: 'Your request is #$position in queue',
                );
              }
            });
          }
          break;
        case 'processing':
          debugPrint('[PredisVideo] Processing: ${request.progress}% complete');
          break;
        default:
          break;
      }
    }, onError: (e, stack) {
      debugPrint('[PredisVideo] Error listening to request: $e\n$stack');
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

      NotificationService.showSuccess(
        context: context,
        title: 'Request Cancelled',
        message: 'Video generation request cancelled successfully',
      );
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Cancel Error',
        message: 'Failed to cancel generation request',
        technicalDetails: e.toString(),
      );
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

      NotificationService.showSuccess(
        context: context,
        title: 'Request Retried',
        message: 'Video generation request queued for retry',
      );
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Retry Error',
        message: 'Failed to retry generation request',
        technicalDetails: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _makeApiRequest(GenerationRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('${_config.baseUrl}/create_video/'),
        headers: _config.headers,
        body: jsonEncode({
          'prompt': request.prompt,
          'brand_id': _config.defaultParams['brand_id'],
          ...?request.metadata,
        }),
      ).timeout(requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 429) {
        throw Exception('Rate limit exceeded. Please try again later.');
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }

  Future<void> _handleError(String requestId, dynamic error) async {
    try {
      final doc = await _firestore.collection('generation_queue').doc(requestId).get();
      if (!doc.exists) return;

      final request = GenerationRequest.fromMap(doc.data()!);
      final retryCount = request.metadata?['retryCount'] as int? ?? 0;

      if (retryCount < maxRetries) {
        final Map<String, dynamic> updatedMetadata = {
          ...?request.metadata,
          'retryCount': retryCount + 1,
        };

        await _firestore.collection('generation_queue').doc(requestId).update({
          'status': 'pending',
          'errorMessage': 'Failed attempt ${retryCount + 1}/$maxRetries: $error',
          'metadata': updatedMetadata,
          'timestamp': DateTime.now(),
        });
      } else {
        await _firestore.collection('generation_queue').doc(requestId).update({
          'status': 'failed',
          'errorMessage': 'Failed after $maxRetries attempts: $error',
          'timestamp': DateTime.now(),
        });
      }
    } catch (e) {
      debugPrint('[PredisVideo] Error handling error: $e');
    }
  }

  Map<String, dynamic> _getRequestData(String requestId, Map<String, dynamic>? params) {
    final Map<String, dynamic> baseMetadata = {
      'content_type': 'video',
      'media_type': 'video',
      'brand_id': _config.defaultParams['brand_id'],
      'input_language': 'english',
      'output_language': 'english',
      'video_type': 'short',
      'duration': '30',
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
} 