import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get user stream for real-time updates
  Stream<UserModel?> getUser(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) {
          if (doc.exists) {
            return UserModel.fromMap(doc.data()!..['uid'] = doc.id);
          }
          return null;
        });
  }

  // Get user by ID (one-time fetch)
  Future<UserModel?> getUserById(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!..['uid'] = doc.id);
      }
      return null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  // Create new user
  Future<void> createUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set(user.toMap());
    } catch (e) {
      print('Error creating user: $e');
      throw e;
    }
  }

  // Update user tokens
  Future<void> updateTokens(String uid, int tokensToAdd) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final currentTokens = userDoc.data()?['tokens'] ?? 0;
        await _firestore.collection('users').doc(uid).update({
          'tokens': currentTokens + tokensToAdd,
        });
      }
    } catch (e) {
      print('Error updating tokens: $e');
      throw e;
    }
  }

  // Update user data
  Future<void> updateUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.uid).update(user.toMap());
    } catch (e) {
      print('Error updating user: $e');
      throw e;
    }
  }
}