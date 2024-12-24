import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Stream<UserModel> getUser(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      return UserModel.fromMap(snapshot.data()!);
    });
  }

  Future<void> updateUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).update(user.toMap());
  }

  Future<void> updateTokens(String uid, int tokens) async {
    await _db.collection('users').doc(uid).update({'tokens': tokens});
  }
}