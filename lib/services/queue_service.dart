import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/generation_request.dart';
import '../models/generation_type.dart';
import '../services/notification_service.dart';
import '../services/token_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

final queueServiceProvider = Provider<QueueService>((ref) {
  return QueueService(
    FirebaseAuth.instance,
    FirebaseDatabase.instance,
    ref.watch(tokenServiceProvider),
  );
});

final queueStreamProvider = StreamProvider<List<GenerationRequest>>((ref) {
  return ref.watch(queueServiceProvider).queueStream;
});

final requestStreamProvider = StreamProvider.family<GenerationRequest?, String>((ref, requestId) {
  return ref.watch(queueServiceProvider).watchRequest(requestId);
});

final userQueueRequestsProvider = StreamProvider<List<GenerationRequest>>((ref) {
  return QueueService(
    FirebaseAuth.instance,
    FirebaseDatabase.instance,
    ref.watch(tokenServiceProvider),
  ).getUserRequestsStream();
});

class QueueService {
  final FirebaseAuth _auth;
  final FirebaseDatabase _rtdb;
  final TokenService _tokenService;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // Rate limiting map
  static final Map<String, int> _apiRequestCounts = {};
  static final Map<String, Timer?> _apiTimers = {};
  
  // Constants
  static const int _maxRequestsPerMinute = 60;
  static const Duration _queueTimeout = Duration(minutes: 1);
  
  // Queue reference
  DatabaseReference get _queueRef => _rtdb.ref('queue');
  
  QueueService(this._auth, this._rtdb, this._tokenService);

  Future<String?> addToQueue({
    required BuildContext context,
    required String prompt,
    required GenerationType type,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        NotificationService.showError(
          context: context,
          title: 'Authentication Error',
          message: 'Please sign in to submit a request.',
        );
        return null;
      }

      // Check API rate limit
      if (!_canMakeApiRequest(type.value)) {
        throw Exception('API rate limit exceeded. Please try again later or switch to a different AI service.');
      }

      // Create request document
      final requestRef = _firestore.collection('generation_queue').doc();
      final request = GenerationRequest(
        id: requestRef.id,
        userId: user.uid,
        type: type,
        prompt: prompt,
        status: 'pending',
        timestamp: DateTime.now(),
        tokenCost: _getTokenCost(type),
        priority: QueuePriority.low,
        readyToProcess: false,
        metadata: metadata,
      );

      // Add to Firestore
      await requestRef.set(request.toMap());

      // Add to RTDB priority queue
      final queueRef = _queueRef.push();
      final queueData = {
        ...request.toJson(),
        'queuedAt': ServerValue.timestamp,
        'timeoutAt': {
          '.sv': 'timestamp',
          '.increment': _queueTimeout.inMilliseconds,
        },
      };
      
      await queueRef.set(queueData);
      
      // Set up auto-cleanup
      _setupQueueCleanup(requestRef.id, type.value);
      
      return requestRef.id;
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Queue Error',
        message: 'Failed to add request to queue.',
        technicalDetails: e.toString(),
      );
      return null;
    }
  }

  Future<void> cancelRequest(String requestId, BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final requestRef = _firestore.collection('generation_queue').doc(requestId);
      final request = await requestRef.get();

      if (!request.exists) throw Exception('Request not found');
      if (request.data()!['userId'] != user.uid) throw Exception('Not authorized');

      // Remove from RTDB queue
      await _queueRef.child(requestId).remove();

      // Update Firestore status
      await requestRef.update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Refund tokens if not started processing
      if (request.data()!['status'] == 'pending') {
        final tokensUsed = request.data()!['tokenCost'] as int;
        await _tokenService.addTokens(tokensUsed);
      }
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Cancel Error',
        message: 'Failed to cancel request.',
        technicalDetails: e.toString(),
      );
    }
  }

  Stream<List<GenerationRequest>> get queueStream {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('generation_queue')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GenerationRequest.fromMap(doc.data()))
            .toList());
  }

  Stream<GenerationRequest?> watchRequest(String requestId) {
    return _firestore
        .collection('generation_queue')
        .doc(requestId)
        .snapshots()
        .map((doc) => doc.exists ? GenerationRequest.fromMap(doc.data()!) : null);
  }

  Future<int> _getActiveRequestsCount(String userId) async {
    final snapshot = await _firestore
        .collection('generation_queue')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'processing'])
        .get();

    return snapshot.docs.length;
  }

  QueuePriority _getPriorityForSubscription(String level) {
    switch (level.toLowerCase()) {
      case 'premium':
      case 'pro':
        return QueuePriority.high;
      case 'plus':
      case 'standard':
        return QueuePriority.medium;
      default:
        return QueuePriority.low;
    }
  }

  int _getTokenCost(GenerationType type) {
    switch (type) {
      case GenerationType.image:
        return 20;
      case GenerationType.video:
        return 50;
      case GenerationType.audio:
        return 30;
      case GenerationType.text:
        return 10;
    }
  }

  void _startQueueCleaner() {
    // Implementation needed
  }

  Future<void> _cleanupQueue() async {
    // Implementation needed
  }

  Future<void> removeFromQueue(String requestId, int tokenCost) async {
    // Implementation needed
  }

  Future<void> updateRequestStatus(
    String requestId,
    String status, {
    String? errorMessage,
    String? outputUrl,
    String? generatedFileName,
  }) async {
    // Implementation needed
  }

  Future<void> dispose() async {
    // Implementation needed
  }

  Future<String?> submitRequest({
    required BuildContext context,
    required String prompt,
    required GenerationType type,
    required Map<String, dynamic> metadata,
  }) async {
    // Implementation needed
    return null;
  }

  Stream<List<GenerationRequest>> getUserRequestsStream() {
    // Implementation needed
    return Stream.value([]);
  }

  Future<void> retryRequest(String requestId, BuildContext context) async {
    // Implementation needed
  }

  // Internal method to process successful generation
  Future<void> completeGeneration(String requestId, String result) async {
    // Implementation needed
  }

  // API rate limiting
  bool _canMakeApiRequest(String serviceId) {
    final count = _apiRequestCounts[serviceId] ?? 0;
    if (count >= _maxRequestsPerMinute) return false;
    
    _apiRequestCounts[serviceId] = count + 1;
    
    // Reset counter after 1 minute
    _apiTimers[serviceId]?.cancel();
    _apiTimers[serviceId] = Timer(const Duration(minutes: 1), () {
      _apiRequestCounts[serviceId] = 0;
      _apiTimers[serviceId] = null;
    });
    
    return true;
  }
  
  // Queue cleanup
  void _setupQueueCleanup(String queueId, String serviceId) {
    Timer(_queueTimeout, () async {
      final snapshot = await _queueRef.child(queueId).get();
      if (snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        if (data['status'] != 'completed') {
          await _queueRef.child(queueId).update({
            'status': 'failed',
            'error': 'Request timed out',
          });
        }
        await _queueRef.child(queueId).remove();
      }
    });
  }
} 