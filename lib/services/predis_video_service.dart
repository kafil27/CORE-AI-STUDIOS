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
  static const int _maxRequestsPerMinute = 30;  // Predis API limit
  static const int _maxTemplateRequestsPerMinute = 10;
  static const Duration _rateLimitWindow = Duration(minutes: 1);
  
  // Queue management
  static const int _maxConcurrentRequests = 5;
  static const Duration _queueCheckInterval = Duration(seconds: 10);
  
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
    final now = DateTime.now();
    final windowStart = now.subtract(_rateLimitWindow);
    
    final requestsRef = _firestore.collection('api_requests')
        .where('type', isEqualTo: type)
        .where('timestamp', isGreaterThanOrEqualTo: windowStart);
    
    final snapshot = await requestsRef.count().get();
    final requestCount = snapshot.count ?? 0;
    
    final limit = type == 'template' 
        ? _maxTemplateRequestsPerMinute 
        : _maxRequestsPerMinute;
    
    return requestCount < limit;
  }

  Future<void> _recordApiRequest(String type) async {
    await _firestore.collection('api_requests').add({
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': _auth.currentUser?.uid,
    });
  }

  Future<int> _getQueuePosition(String requestId) async {
    final queueSnapshot = await _firestore
        .collection('generation_queue')
        .where('status', isEqualTo: GenerationStatus.queued.value)
        .orderBy('createdAt')
        .get();
    
    final position = queueSnapshot.docs
        .indexWhere((doc) => doc.id == requestId);
    
    return position >= 0 ? position + 1 : 0;
  }

  Future<List<GenerationRequest>> getRecentVideos({
    required BuildContext context,
    int limit = 5,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // First try to get from Firestore cache
      final snapshot = await _firestore
          .collection('generation_queue')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: GenerationType.video.toString().split('.').last)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      // Then fetch from Predis API
      final response = await http.get(
        Uri.parse('https://brain.predis.ai/predis_api/v1/get_posts/'),
        headers: {
          'Authorization': 'Bearer ${_config.apiKey}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 429) {
        // Handle rate limit
        debugPrint('Rate limit exceeded for get_posts API');
        // Return cached data
        return snapshot.docs
            .map((doc) => GenerationRequest.fromMap(doc.data()))
            .toList();
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch videos from Predis API');
      }

      final data = jsonDecode(response.body);
      final posts = (data['posts'] as List)
          .where((post) => post['media_type'] == 'video')
          .take(limit)
          .map((post) => GenerationRequest(
                id: post['post_id'],
                userId: user.uid,
                type: GenerationType.video,
                prompt: post['caption'] ?? '',
                status: GenerationStatus.completed,
                createdAt: DateTime.now(), // API doesn't provide timestamp
                updatedAt: DateTime.now(),
                progress: 100,
                priority: 1,
                attempts: 0,
                maxAttempts: 3,
                retryCount: 0,
                tokensUsed: 100,
                metadata: {
                  ...post,
                  'urls': post['urls'],
                  'media_type': 'video',
                },
              ))
          .toList();

      // Update cache
      final batch = _firestore.batch();
      for (final post in posts) {
        batch.set(
          _firestore.collection('generation_queue').doc(post.id),
          post.toMap(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      return posts;
    } catch (e) {
      debugPrint('Error fetching recent videos: $e');
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

      // Check rate limit before proceeding
      final withinLimit = await _checkRateLimit('video');
      if (!withinLimit) {
        NotificationService.showError(
          context: context,
          title: 'Rate Limit Exceeded',
          message: 'Please try again in a minute',
          technicalDetails: 'Maximum requests per minute reached',
        );
        return null;
      }

      // Create generation request in Firebase
      final requestRef = _firestore.collection('generation_queue').doc();
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
          ...?additionalParams,
        },
        tokensUsed: 100,
      );

      // Save request to Firestore
      await requestRef.set(request.toMap());
      
      // Send request to Predis API
      final response = await http.post(
        Uri.parse('https://brain.predis.ai/predis_api/v1/create_content/'),
        headers: {
          'Authorization': 'Bearer ${_config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'brand_id': _config.defaultParams['brand_id'],
          'media_type': 'video',
          'caption': prompt,
          ...?additionalParams,
        }),
      );

      if (response.statusCode == 429) {
        // Update request status to rate limited
        await requestRef.update({
          'status': GenerationStatus.failed.value,
          'error': 'Rate limit exceeded. Will retry automatically.',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return requestRef.id;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to submit video generation request to Predis API');
      }

      // Record API request for rate limiting
      await _recordApiRequest('video');

      // Get queue position
      final position = await _getQueuePosition(requestRef.id);
      
      NotificationService.showSuccess(
        context: context,
        title: 'Request Queued',
        message: position > 1 
            ? 'Your request is #$position in queue'
            : 'Your video generation request has been queued',
      );

      // Start listening to request status
      _listenToRequestStatus(requestRef.id, context);

      return requestRef.id;
    } catch (e) {
      debugPrint('Error submitting video generation request: $e');
      NotificationService.showError(
        context: context,
        title: 'Request Error',
        message: 'Failed to submit video generation request',
        technicalDetails: e.toString(),
      );
      return null;
    }
  }

  void _listenToRequestStatus(String requestId, BuildContext context) {
    _firestore
        .collection('generation_queue')
        .doc(requestId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final request = GenerationRequest.fromMap(snapshot.data()!);
      
      switch (request.status) {
        case GenerationStatus.completed:
          NotificationService.showSuccess(
            context: context,
            title: 'Video Generated',
            message: 'Your video has been generated successfully',
            playSound: true,
          );
          break;
        case GenerationStatus.failed:
          final errorMessage = request.error;
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
          _getQueuePosition(requestId).then((position) {
            if (position > 1) {
              NotificationService.showInfo(
                context: context,
                title: 'Queue Update',
                message: 'Your request is #$position in queue',
              );
            }
          });
          break;
        default:
          // Don't show notifications for other states
          break;
      }
    });
  }

  Future<void> cancelRequest(String requestId, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await _firestore
          .collection('generation_queue')
          .doc(requestId)
          .update({
        'status': GenerationStatus.cancelled.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      NotificationService.showSuccess(
        context: context,
        title: 'Request Cancelled',
        message: 'Video generation request has been cancelled',
      );
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Error',
        message: 'Failed to cancel request',
        technicalDetails: e.toString(),
      );
    }
  }

  Future<void> retryRequest(String requestId, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await _firestore
          .collection('generation_queue')
          .doc(requestId)
          .update({
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
        message: 'Video generation request has been queued again',
      );
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Error',
        message: 'Failed to retry request',
        technicalDetails: e.toString(),
      );
    }
  }
} 