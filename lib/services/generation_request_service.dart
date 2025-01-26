import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/generation_request.dart';
import '../models/generation_type.dart' as types;
import '../services/notification_service.dart';
import '../services/token_service.dart';

final generationRequestProvider = StreamProvider.family<GenerationRequest?, String>((ref, requestId) {
  return FirebaseFirestore.instance
      .collection('generation_queue')
      .doc(requestId)
      .snapshots()
      .map((doc) => doc.exists ? GenerationRequest.fromMap(doc.data()!) : null);
});

final userRequestsProvider = StreamProvider<List<GenerationRequest>>((ref) {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('generation_queue')
      .where('userId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => GenerationRequest.fromMap(doc.data()))
          .toList());
});

class GenerationRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TokenService _tokenService = TokenService(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );

  int _getTokenCost(types.GenerationType type) {
    switch (type) {
      case types.GenerationType.image:
        return 20;
      case types.GenerationType.video:
        return 50;
      case types.GenerationType.audio:
        return 30;
    }
    return 20; // Default cost
  }

  Future<String?> submitRequest({
    required BuildContext context,
    required String prompt,
    required types.GenerationType type,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        NotificationService.showError(
          title: 'Authentication Error',
          message: 'Please sign in to submit a generation request.',
          context: context,
        );
        return null;
      }

      // Check token balance
      final tokenCost = _getTokenCost(type);
      await _tokenService.checkTokenBalance(
        tokenCost,
        serviceType: '${type.toString().split('.').last} Generation',
      );

      // Create request document
      final requestRef = _firestore.collection('generation_queue').doc();
      final request = GenerationRequest(
        id: requestRef.id,
        userId: user.uid,
        type: type,
        prompt: prompt,
        status: types.GenerationStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        priority: 1,
        attempts: 0,
        maxAttempts: 3,
        progress: 0,
        retryCount: 0,
        metadata: metadata,
        tokensUsed: tokenCost,
      );

      // Save request to Firestore
      await requestRef.set(request.toMap());

      // Deduct tokens
      await _tokenService.deductTokens(
        tokenCost,
        '${type.toString().split('.').last} Generation',
        prompt: prompt,
        outputUrl: '',
        generatedFileName: '',
        serviceSpecificData: metadata,
      );

      return requestRef.id;
    } catch (e) {
      if (e is TokenServiceException) {
        if (e.error == TokenServiceError.insufficientTokens) {
          final balance = await _tokenService.getTokenBalance();
          NotificationService.showInsufficientBalance(
            context: context,
            required: _getTokenCost(type),
            current: balance,
            serviceType: '${type.toString().split('.').last} Generation',
            onPurchase: () {
              Navigator.pushNamed(
                context,
                '/profile',
                arguments: 'showTokens',
              );
            },
          );
        } else {
          NotificationService.showError(
            context: context,
            title: 'Token Error',
            message: e.message,
            showPopup: true,
          );
        }
      } else {
        NotificationService.showError(
          context: context,
          title: 'Request Error',
          message: 'Failed to submit generation request.',
          technicalDetails: e.toString(),
          showPopup: true,
        );
      }
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

      await requestRef.update({
        'status': types.GenerationStatus.cancelled.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Refund tokens if the request hasn't started processing
      if (request.data()!['status'] == types.GenerationStatus.pending.value) {
        final tokensUsed = request.data()!['tokensUsed'] as int;
        await _tokenService.deductTokens(
          -tokensUsed, // Negative value to add tokens back
          '${request.data()!['type']} Generation Cancelled',
          prompt: '',
          outputUrl: '',
          generatedFileName: '',
          serviceSpecificData: {'requestId': requestId},
        );
      }
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Cancel Error',
        message: 'Failed to cancel generation request.',
        technicalDetails: e.toString(),
        showPopup: true,
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

      // Check if request can be retried
      final retryCount = request.data()!['retryCount'] as int;
      final maxRetries = 3;
      if (retryCount >= maxRetries) {
        throw Exception('Maximum retry attempts reached');
      }

      // Update request status
      await requestRef.update({
        'status': types.GenerationStatus.pending.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'retryCount': FieldValue.increment(1),
        'attempts': 0,
        'progress': 0,
        'error': null,
      });
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Retry Error',
        message: 'Failed to retry generation request.',
        technicalDetails: e.toString(),
        showPopup: true,
      );
    }
  }
} 