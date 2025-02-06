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

  static const int _maxQueueSize = 100;
  static const int _maxConcurrentRequests = 10;
  static const Duration _queueCleanupInterval = Duration(hours: 24);

  QueueService(this._auth, this._rtdb, this._tokenService) {
    _startQueueCleaner();
  }

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

      // Check queue size limits
      final activeRequests = await _getActiveRequestsCount(user.uid);
      if (activeRequests >= _maxQueueSize) {
        NotificationService.showError(
          context: context,
          title: 'Queue Full',
          message: 'Please wait for your current requests to complete.',
        );
        return null;
      }

      // Determine user's priority level
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final subscriptionLevel = userDoc.data()?['subscriptionLevel'] ?? 'free';
      final priority = _getPriorityForSubscription(subscriptionLevel);

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
        priority: priority,
        readyToProcess: false,
        metadata: {
          ...metadata,
          'subscriptionLevel': subscriptionLevel,
        },
      );

      // Add to Firestore
      await requestRef.set(request.toMap());

      // Add to RTDB priority queue
      final queueRef = _rtdb.ref('queues/${priority.value}/${request.id}');
      await queueRef.set({
        'timestamp': ServerValue.timestamp,
        'userId': user.uid,
      });

      return request.id;
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
      final priority = QueuePriority.fromString(request.data()!['priority']);
      await _rtdb.ref('queues/${priority.value}/$requestId').remove();

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
    Timer.periodic(_queueCleanupInterval, (_) => _cleanupQueue());
  }

  Future<void> _cleanupQueue() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      
      // Clean Firestore
      final oldRequests = await _firestore
          .collection('generation_queue')
          .where('timestamp', isLessThan: cutoff)
          .where('status', whereIn: ['completed', 'failed', 'cancelled'])
          .get();

      final batch = _firestore.batch();
      for (var doc in oldRequests.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Clean RTDB
      for (var priority in QueuePriority.values) {
        final oldQueueItems = await _rtdb
            .ref('queues/${priority.value}')
            .orderByChild('timestamp')
            .endAt(cutoff.millisecondsSinceEpoch)
            .get();

        if (oldQueueItems.exists) {
          final updates = <String, dynamic>{};
          (oldQueueItems.value as Map).forEach((key, _) {
            updates[key] = null;
          });
          await _rtdb.ref('queues/${priority.value}').update(updates);
        }
      }
    } catch (e) {
      print('Error cleaning queue: $e');
    }
  }

  Future<void> removeFromQueue(String requestId, int tokenCost) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // First release the token reservation
      await _tokenService.releaseTokenReservation(requestId, tokenCost);

      // Then remove from queue
      await _rtdb
          .ref('queues/${user.uid}/$requestId')
          .remove();

    } catch (e) {
      print('Error removing from queue: $e');
      rethrow;
    }
  }

  Future<void> updateRequestStatus(
    String requestId,
    String status, {
    String? errorMessage,
    String? outputUrl,
    String? generatedFileName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final updates = <String, dynamic>{
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      if (errorMessage != null) updates['errorMessage'] = errorMessage;
      if (outputUrl != null) updates['outputUrl'] = outputUrl;
      if (generatedFileName != null) updates['generatedFileName'] = generatedFileName;

      await _rtdb
          .ref('queues/${user.uid}/$requestId')
          .update(updates);

    } catch (e) {
      print('Error updating request status: $e');
      rethrow;
    }
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
} 