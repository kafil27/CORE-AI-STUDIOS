import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

final tokenBalanceProvider = StreamProvider<int>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((doc) => doc.data()?['tokens'] ?? 0);
});

class TokenBalanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> checkBalance(BuildContext context, int requiredTokens, String serviceType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        NotificationService.showError(
          context: context,
          title: 'Authentication Error',
          message: 'Please sign in to continue.',
          showPopup: true,
        );
        return false;
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();
      final currentBalance = doc.data()?['tokens'] ?? 0;

      if (currentBalance < requiredTokens) {
        NotificationService.showInsufficientBalance(
          context: context,
          required: requiredTokens,
          current: currentBalance,
          serviceType: serviceType,
          onPurchase: () {
            // Navigate to purchase screen or show purchase options
            Navigator.pushNamed(context, '/profile');
          },
        );
        return false;
      }

      return true;
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Balance Check Error',
        message: 'Failed to check token balance.',
        technicalDetails: e.toString(),
        showPopup: true,
      );
      return false;
    }
  }

  Future<void> deductTokens(String userId, int tokens, BuildContext context) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'tokens': FieldValue.increment(-tokens),
      });
      NotificationService.showSuccess(
        context: context,
        title: 'Tokens Deducted',
        message: '-$tokens tokens from your balance',
      );
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Token Error',
        message: 'Failed to deduct tokens.',
        technicalDetails: e.toString(),
        showPopup: false,
      );
      rethrow;
    }
  }

  Future<void> addTokens(String userId, int tokens, BuildContext context) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'tokens': FieldValue.increment(tokens),
      });
      NotificationService.showSuccess(
        context: context,
        title: 'Tokens Added',
        message: '+$tokens tokens to your balance',
      );
    } catch (e) {
      NotificationService.showError(
        context: context,
        title: 'Token Error',
        message: 'Failed to add tokens.',
        technicalDetails: e.toString(),
        showPopup: false,
      );
      rethrow;
    }
  }

  Future<Map<String, int>> getTokenSnapshot(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final currentBalance = doc.data()?['tokens'] ?? 0;
      return {
        'before': currentBalance,
        'after': currentBalance,
        'deducted': 0,
      };
    } catch (e) {
      print('Error getting token snapshot: $e');
      rethrow;
    }
  }
} 