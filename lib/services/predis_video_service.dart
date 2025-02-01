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
  final AIServiceConfig _config;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isInitialized = false;
  
  // Rate limiting constants
  static const int _maxRequestsPerMinute = 60;  // Global Predis API limit per key
  static const int _maxTemplateRequestsPerMinute = 10;
  static const Duration _rateLimitWindow = Duration(minutes: 1);
  
  // Queue management
  static const int _maxConcurrentRequests = 5;
  static const Duration _queueCheckInterval = Duration(seconds: 10);
  static const Duration _queueTimeout = Duration(minutes: 2);
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  
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

  Future<bool> _checkRateLimit(String type) async {
    try {
      final now = DateTime.now();
      final windowStart = now.subtract(_rateLimitWindow);
      
      // Check global API key rate limit
      final requestsRef = _firestore.collection('api_requests')
          .where('api_key', isEqualTo: _config.apiKey)
          .where('timestamp', isGreaterThanOrEqualTo: windowStart);
      
      final snapshot = await requestsRef.get();
      final requestCount = snapshot.docs.length; // Use docs.length instead of count()
      
      if (requestCount >= _maxRequestsPerMinute) {
        debugPrint('[PredisVideo] API key rate limit exceeded: $requestCount requests in last minute');
        return false;
      }

      // Also check if we have an active request in processing state
      final activeRequestsRef = _firestore.collection('generation_queue')
          .where('userId', isEqualTo: _auth.currentUser?.uid)
          .where('status', isEqualTo: GenerationStatus.processing.value)
          .where('type', isEqualTo: GenerationType.video.toString().split('.').last);
      
      final activeSnapshot = await activeRequestsRef.get();
      if (activeSnapshot.docs.isNotEmpty) {
        debugPrint('[PredisVideo] User has active request in processing');
        return false;
      }
      
      return true;
    } catch (e, stack) {
      debugPrint('[PredisVideo] Rate limit check error: $e\n$stack');
      return true; // Allow request on error to prevent blocking
    }
  }

  Future<void> _recordApiRequest(String type) async {
    await _firestore.collection('api_requests').add({
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': _auth.currentUser?.uid,
      'api_key': _config.apiKey,
    });
  }

  Future<void> _cleanupQueue() async {
    try {
      debugPrint('[PredisVideo] Starting queue cleanup');
      final user = _auth.currentUser;
      if (user == null) return;

      final timeoutThreshold = DateTime.now().subtract(_queueTimeout);
      final requestTimeoutThreshold = DateTime.now().subtract(_requestTimeout);
      
      // Get stale requests (in queue too long)
      final staleRequests = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: GenerationType.video.toString().split('.').last)
          .where('status', whereIn: [
            GenerationStatus.queued.value,
            GenerationStatus.processing.value,
          ])
          .where('updatedAt', isLessThan: timeoutThreshold)
          .get();

      // Get timed out requests (no response from API)
      final timedOutRequests = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: GenerationType.video.toString().split('.').last)
          .where('status', isEqualTo: GenerationStatus.processing.value)
          .where('updatedAt', isLessThan: requestTimeoutThreshold)
          .get();

      final batch = _firestore.batch();
      
      // Handle stale requests
      for (final doc in staleRequests.docs) {
        final data = doc.data();
        final retryCount = data['retryCount'] as int? ?? 0;
        
        if (retryCount < _maxRetries) {
          // Auto-retry
          batch.update(doc.reference, {
            'status': GenerationStatus.queued.value,
            'retryCount': FieldValue.increment(1),
            'error': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Mark as failed after max retries
          batch.update(doc.reference, {
            'status': GenerationStatus.failed.value,
            'error': 'Request timed out after ${_maxRetries} retries',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // Handle timed out requests
      for (final doc in timedOutRequests.docs) {
        final data = doc.data();
        final retryCount = data['retryCount'] as int? ?? 0;
        
        if (retryCount < _maxRetries) {
          // Auto-retry
          batch.update(doc.reference, {
            'status': GenerationStatus.queued.value,
            'retryCount': FieldValue.increment(1),
            'error': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Mark as failed after max retries
          batch.update(doc.reference, {
            'status': GenerationStatus.failed.value,
            'error': 'API request timed out after ${_maxRetries} retries',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
      debugPrint('[PredisVideo] Queue cleanup completed. Processed ${staleRequests.docs.length} stale and ${timedOutRequests.docs.length} timed out requests');
    } catch (e, stack) {
      debugPrint('[PredisVideo] Queue cleanup error: $e\n$stack');
    }
  }

  Future<int> _getQueuePosition(String requestId) async {
    try {
      debugPrint('[PredisVideo] Getting queue position for request: $requestId');
      final user = _auth.currentUser;
      if (user == null) return 0;

      // First cleanup the queue
      await _cleanupQueue();

      // Get only active requests in queue
      final queueSnapshot = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: GenerationStatus.queued.value)
          .where('type', isEqualTo: GenerationType.video.toString().split('.').last)
          .orderBy('createdAt')
          .orderBy('__name__')
          .get();
      
      final position = queueSnapshot.docs
          .indexWhere((doc) => doc.id == requestId);
      
      debugPrint('[PredisVideo] Queue position: ${position >= 0 ? position + 1 : 0}');
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

      // Get next request in queue
      final nextRequest = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: GenerationStatus.queued.value)
          .where('type', isEqualTo: GenerationType.video.toString().split('.').last)
          .orderBy('createdAt')
          .limit(1)
          .get();

      if (nextRequest.docs.isEmpty) return;

      final request = nextRequest.docs.first;
      final data = request.data();

      // Start processing
      await request.reference.update({
        'status': GenerationStatus.processing.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'startedAt': FieldValue.serverTimestamp(),
      });

      // Make API call to Predis with timeout
      try {
        final response = await http.post(
          Uri.parse('https://brain.predis.ai/predis_api/v1/create_video/'),
          headers: {
            'Authorization': 'Bearer ${_config.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'prompt': data['prompt'],
            'brand_id': _config.defaultParams['brand_id'],
            ...data['metadata'],
          }),
        ).timeout(_requestTimeout);

        if (response.statusCode == 200) {
          await request.reference.update({
            'status': GenerationStatus.completed.value,
            'progress': 100,
            'updatedAt': FieldValue.serverTimestamp(),
            'result': jsonDecode(response.body),
          });
        } else if (response.statusCode == 429) {
          // Rate limit hit, requeue with backoff
          await request.reference.update({
            'status': GenerationStatus.queued.value,
            'error': 'Rate limited, will retry automatically',
            'updatedAt': FieldValue.serverTimestamp(),
            'nextRetryAt': FieldValue.serverTimestamp(),
          });
        } else {
          final retryCount = data['retryCount'] as int? ?? 0;
          if (retryCount < _maxRetries) {
            // Auto-retry on error
            await request.reference.update({
              'status': GenerationStatus.queued.value,
              'retryCount': FieldValue.increment(1),
              'error': 'API Error: ${response.statusCode}, retrying...',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            await request.reference.update({
              'status': GenerationStatus.failed.value,
              'error': 'API Error: ${response.statusCode} after ${_maxRetries} retries',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (e) {
        final retryCount = data['retryCount'] as int? ?? 0;
        if (retryCount < _maxRetries) {
          // Auto-retry on error
          await request.reference.update({
            'status': GenerationStatus.queued.value,
            'retryCount': FieldValue.increment(1),
            'error': 'Request error: $e, retrying...',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await request.reference.update({
            'status': GenerationStatus.failed.value,
            'error': 'Request failed after ${_maxRetries} retries: $e',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e, stack) {
      debugPrint('[PredisVideo] Queue processing error: $e\n$stack');
    }
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
      
      final request = GenerationRequest(
        id: requestRef.id,
        userId: user.uid,
        type: GenerationType.video,
        prompt: prompt,
        status: GenerationStatus.queued,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        priority: 1,
        attempts: 0,
        maxAttempts: 3,
        progress: 0,
        retryCount: 0,
        metadata: {
          'prompt': prompt,
          'content_type': 'video',
          'media_type': 'video',
          'brand_id': _config.defaultParams['brand_id'],
          'input_language': 'english',
          'output_language': 'english',
          'video_type': 'short',
          'duration': '30',
          'api_key': _config.apiKey,
          ...?additionalParams,
        },
        tokensUsed: 100,
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
        case GenerationStatus.completed:
          // Deduct tokens only on successful completion
          await _firestore.collection('users').doc(request.userId).update({
            'tokens': FieldValue.increment(-request.tokensUsed),
          });
          NotificationService.showSuccess(
            context: context,
            title: 'Video Generated',
            message: 'Your video has been generated successfully',
            playSound: true,
          );
          break;
        case GenerationStatus.failed:
          final errorMessage = request.error;
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
              message: request.error ?? 'Failed to generate video',
              showPopup: true,
            );
          }
          break;
        case GenerationStatus.queued:
          if (request.status == GenerationStatus.queued) {
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
        case GenerationStatus.processing:
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
} 