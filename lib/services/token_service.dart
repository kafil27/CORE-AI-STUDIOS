import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TokenServiceError {
  insufficientTokens,
  networkError,
  serverError,
  unknownError,
}

class TokenServiceException implements Exception {
  final TokenServiceError error;
  final String message;

  TokenServiceException(this.error, this.message);

  @override
  String toString() => message;
}

class TokenCost {
  static const int video = 30;
  static const int audio = 20;
  static const int image = 10;
  static const int chat = 5;
}

class TokenService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Stream<int> get tokenBalance {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value(0);
    
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.data()?['tokens'] as int? ?? 0);
  }

  Future<void> checkTokenBalance(int requiredTokens) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw TokenServiceException(
        TokenServiceError.serverError,
        'User not authenticated',
      );
    }

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final currentTokens = doc.data()?['tokens'] as int? ?? 0;

      if (currentTokens < requiredTokens) {
        throw TokenServiceException(
          TokenServiceError.insufficientTokens,
          'Insufficient tokens. Required: $requiredTokens, Available: $currentTokens',
        );
      }
    } catch (e) {
      if (e is TokenServiceException) rethrow;
      throw TokenServiceException(
        TokenServiceError.networkError,
        'Failed to check token balance: ${e.toString()}',
      );
    }
  }

  Future<void> deductTokens(int amount, String serviceType) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw TokenServiceException(
        TokenServiceError.serverError,
        'User not authenticated',
      );
    }

    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(userId);
    final usageRef = _firestore.collection('usage_history').doc();

    try {
      // Create usage record
      batch.set(usageRef, {
        'userId': userId,
        'serviceType': serviceType,
        'tokensUsed': amount,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update user's token balance
      batch.update(userRef, {
        'tokens': FieldValue.increment(-amount),
      });

      await batch.commit();
    } catch (e) {
      throw TokenServiceException(
        TokenServiceError.serverError,
        'Failed to deduct tokens: ${e.toString()}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getRecentUsage() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return [];

    try {
      final snapshot = await _firestore
          .collection('usage_history')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'serviceType': data['serviceType'],
          'tokensUsed': data['tokensUsed'],
          'timestamp': (data['timestamp'] as Timestamp).toDate(),
        };
      }).toList();
    } catch (e) {
      print('Error fetching recent usage: $e');
      return [];
    }
  }
} 