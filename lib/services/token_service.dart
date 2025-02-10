import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TokenServiceError {
  insufficientTokens,
  invalidAmount,
  authenticationRequired,
  serverError,
}

class TokenServiceException implements Exception {
  final String message;
  final TokenServiceError error;

  TokenServiceException(this.message, this.error);

  @override
  String toString() => message;
}

final tokenServiceProvider = Provider<TokenService>((ref) {
  return TokenService(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});

class TokenCost {
  static const int video = 30;
  static const int audio = 20;
  static const int image = 10;
  static const int chat = 5;
}

class TokenService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _tokenBalanceController = StreamController<int>.broadcast();

  TokenService(this._firestore, this._auth);

  Stream<int> get tokenBalance => _tokenBalanceController.stream;

  Future<int> getTokenBalance() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw TokenServiceException(
        'Authentication required',
        TokenServiceError.authenticationRequired,
      );
    }

    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data()?['tokens'] as int? ?? 0;
  }

  Future<void> checkTokenBalance(int required, {String? serviceType}) async {
    final balance = await getTokenBalance();
    if (balance < required) {
      throw TokenServiceException(
        'Insufficient tokens for $serviceType. Required: $required, Available: $balance',
        TokenServiceError.insufficientTokens,
      );
    }
  }

  Future<void> addTokens(int amount) async {
    if (amount <= 0) {
      throw TokenServiceException(
        'Invalid token amount',
        TokenServiceError.invalidAmount,
      );
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw TokenServiceException(
        'Authentication required',
        TokenServiceError.authenticationRequired,
      );
    }

    await _firestore.collection('users').doc(user.uid).update({
      'tokens': FieldValue.increment(amount),
    });
  }

  Future<void> deductTokens(
    int amount,
    String serviceType, {
    String? prompt,
    String? outputUrl,
    String? generatedFileName,
    Map<String, dynamic>? serviceSpecificData,
  }) async {
    if (amount <= 0) {
      throw TokenServiceException(
        'Invalid token amount',
        TokenServiceError.invalidAmount,
      );
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw TokenServiceException(
        'Authentication required',
        TokenServiceError.authenticationRequired,
      );
    }

    // Start a transaction to ensure atomic updates
    await _firestore.runTransaction((transaction) async {
      final userDoc = await transaction.get(
        _firestore.collection('users').doc(user.uid),
      );

      final currentTokens = userDoc.data()?['tokens'] as int? ?? 0;
      if (currentTokens < amount) {
        throw TokenServiceException(
          'Insufficient tokens',
          TokenServiceError.insufficientTokens,
        );
      }

      // Deduct tokens
      transaction.update(
        _firestore.collection('users').doc(user.uid),
        {'tokens': FieldValue.increment(-amount)},
      );

      // Log the transaction
      transaction.set(
        _firestore
            .collection('users')
            .doc(user.uid)
            .collection('token_history')
            .doc(),
        {
          'amount': -amount,
          'type': serviceType,
          'timestamp': FieldValue.serverTimestamp(),
          'prompt': prompt,
          'outputUrl': outputUrl,
          'generatedFileName': generatedFileName,
          'serviceSpecificData': serviceSpecificData,
        },
      );
    });
  }

  Future<void> reserveTokens(
    int amount,
    String requestId,
    String description,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw TokenServiceException(
        'Authentication required',
        TokenServiceError.authenticationRequired,
      );
    }

    await _firestore.runTransaction((transaction) async {
      final userDoc = await transaction.get(
        _firestore.collection('users').doc(user.uid),
      );

      final currentTokens = userDoc.data()?['tokens'] as int? ?? 0;
      if (currentTokens < amount) {
        throw TokenServiceException(
          'Insufficient tokens',
          TokenServiceError.insufficientTokens,
        );
      }

      // Create reservation
      transaction.set(
        _firestore
            .collection('users')
            .doc(user.uid)
            .collection('token_reservations')
            .doc(requestId),
        {
          'amount': amount,
          'description': description,
          'timestamp': FieldValue.serverTimestamp(),
        },
      );

      // Update available tokens
      transaction.update(
        _firestore.collection('users').doc(user.uid),
        {'tokens': FieldValue.increment(-amount)},
      );
    });
  }

  Future<void> releaseTokenReservation(String requestId, int amount) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw TokenServiceException(
        'Authentication required',
        TokenServiceError.authenticationRequired,
      );
    }

    await _firestore.runTransaction((transaction) async {
      // Delete reservation
      transaction.delete(
        _firestore
            .collection('users')
            .doc(user.uid)
            .collection('token_reservations')
            .doc(requestId),
      );

      // Return tokens
      transaction.update(
        _firestore.collection('users').doc(user.uid),
        {'tokens': FieldValue.increment(amount)},
      );
    });
  }

  @override
  void dispose() {
    _tokenBalanceController.close();
  }

  Future<List<Map<String, dynamic>>> getRecentUsage({int limit = 10}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw TokenServiceException(
        'User not authenticated',
        TokenServiceError.authenticationRequired,
      );

      final snapshot = await _firestore
          .collection('usage_history')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        // Convert Firestore timestamp to DateTime
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] = (data['timestamp'] as Timestamp).toDate();
        }
        return data;
      }).toList();
    } catch (e) {
      throw TokenServiceException(
        'Failed to get usage history: $e',
        TokenServiceError.serverError,
      );
    }
  }
} 