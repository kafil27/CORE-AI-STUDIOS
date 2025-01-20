import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

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
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final _tokenBalanceController = StreamController<int>.broadcast();

  TokenService(this._auth, this._firestore);

  Stream<int> get tokenBalance => _tokenBalanceController.stream;

  Future<void> checkTokenBalance(int amount, {String? serviceType}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) throw Exception('User document not found');

      final balance = doc.data()?['tokens'] as int? ?? 0;
      if (balance < amount) {
        throw TokenServiceException(
          TokenServiceError.insufficientTokens,
          'Insufficient tokens. Required: $amount, Available: $balance',
        );
      }
    } catch (e) {
      if (e is TokenServiceException) rethrow;
      throw TokenServiceException(
        TokenServiceError.unknownError,
        'Failed to check token balance: ${e.toString()}',
      );
    }
  }

  Future<int> getTokenBalance() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) throw Exception('User document not found');

      final balance = doc.data()?['tokens'] as int? ?? 0;
      _tokenBalanceController.add(balance);
      return balance;
    } catch (e) {
      throw Exception('Failed to get token balance: ${e.toString()}');
    }
  }

  Future<void> deductTokens(
    int amount,
    String serviceType, {
    String? prompt,
    String? modelId,
    String? outputUrl,
    String? generatedFileName,
    Map<String, dynamic>? serviceSpecificData,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get current token balance first
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw Exception('User document not found');

      final currentBalance = userDoc.data()?['tokens'] as int? ?? 0;
      if (currentBalance < amount) {
        throw Exception('Insufficient tokens. Required: $amount, Available: $currentBalance');
      }

      // Get current timestamp
      final now = DateTime.now();
      final isoString = now.toIso8601String();

      // Create usage history document
      final usageRef = _firestore.collection('usage_history').doc();
      final userRef = _firestore.collection('users').doc(user.uid);

      // Prepare usage data
      final Map<String, dynamic> usageData = {
        'userId': user.uid,
        'timestamp': now.millisecondsSinceEpoch,
        'timestamp_iso': isoString,
        'serviceType': serviceType,
        'tokensUsed': amount,
        'status': 'completed',
        'tokenBalanceSnapshot': {
          'before': currentBalance,
          'deducted': amount,
          'after': currentBalance - amount,
          'timestamp': isoString,
        },
        'metadata': {
          'device': 'web',
          'version': '1.0.0',
          'platform': 'web',
          'created_at': isoString,
          'updated_at': isoString,
        },
      };

      // Add optional fields if provided
      if (prompt?.isNotEmpty == true) usageData['prompt'] = prompt;
      if (modelId?.isNotEmpty == true) usageData['modelId'] = modelId;
      if (outputUrl?.isNotEmpty == true) usageData['outputUrl'] = outputUrl;
      if (generatedFileName?.isNotEmpty == true) usageData['generatedFileName'] = generatedFileName;

      // Add service specific data if provided
      if (serviceSpecificData != null && serviceSpecificData.isNotEmpty) {
        serviceSpecificData.removeWhere((key, value) => value == null);
        usageData['serviceData'] = {
          ...serviceSpecificData,
          'timestamp': isoString,
        };
      }

      // Update token balance and create usage history in a batch
      final batch = _firestore.batch();

      // Update user document
      batch.update(userRef, {
        'tokens': currentBalance - amount,
        'last_token_update': now.millisecondsSinceEpoch,
        'token_history': FieldValue.arrayUnion([{
          'amount': -amount,
          'balance': currentBalance - amount,
          'type': 'deduction',
          'serviceType': serviceType,
          'timestamp': now.millisecondsSinceEpoch,
        }]),
      });

      // Create usage history
      batch.set(usageRef, usageData);

      // Commit the batch
      await batch.commit();
      
      // Notify listeners of token balance change
      _tokenBalanceController.add(currentBalance - amount);
    } catch (e) {
      print('Token deduction error: $e');
      if (e.toString().contains('INVALID_ARGUMENT')) {
        throw Exception('Failed to save usage history: Data too large');
      } else if (e.toString().contains('NOT_FOUND')) {
        throw Exception('User document not found');
      } else if (e.toString().contains('PERMISSION_DENIED')) {
        throw Exception('Permission denied: Please sign in again');
      }
      throw Exception('Failed to process tokens: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    _tokenBalanceController.close();
  }

  Future<List<Map<String, dynamic>>> getRecentUsage() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return [];

    try {
      final snapshot = await _firestore
          .collection('usage_history')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get()
          .timeout(
            Duration(seconds: 10),
            onTimeout: () {
              throw TokenServiceException(
                TokenServiceError.serverError,
                'Request timed out. The index might still be building.',
              );
            },
          );

      if (snapshot.docs.isEmpty) return [];

      return snapshot.docs.map((doc) {
        final data = doc.data();
        Map<String, dynamic> result = {
          'id': doc.id,
          'serviceType': data['serviceType'] ?? 'unknown',
          'tokensUsed': data['tokensUsed'] ?? 0,
          'timestamp': data['timestamp'] != null 
              ? (data['timestamp'] as Timestamp).toDate()
              : DateTime.now(),
          'status': data['status'] ?? 'completed',
        };

        // Add optional fields if they exist
        if (data['prompt'] != null) result['prompt'] = data['prompt'];
        if (data['outputUrl'] != null) result['outputUrl'] = data['outputUrl'];
        if (data['errorMessage'] != null) result['errorMessage'] = data['errorMessage'];
        if (data['generatedFileName'] != null) result['generatedFileName'] = data['generatedFileName'];
        if (data['modelId'] != null) result['modelId'] = data['modelId'];
        if (data['tokenBalanceSnapshot'] != null) result['tokenBalanceSnapshot'] = data['tokenBalanceSnapshot'];
        if (data['metadata'] != null) result['metadata'] = data['metadata'];
        if (data['serviceData'] != null) result['serviceData'] = data['serviceData'];

        return result;
      }).toList();
    } catch (e) {
      print('Error fetching recent usage: $e');
      if (e.toString().contains('failed-precondition') || 
          e.toString().contains('requires an index')) {
        throw TokenServiceException(
          TokenServiceError.serverError,
          'The system is being prepared for first use. Please try again in a few minutes.',
        );
      }
      if (e is TokenServiceException) rethrow;
      throw TokenServiceException(
        TokenServiceError.networkError,
        'Failed to fetch usage history. Please check your connection.',
      );
    }
  }
} 