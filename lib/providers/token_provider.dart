import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/token_service.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final tokenServiceProvider = Provider<TokenService>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final firestore = ref.watch(firestoreProvider);
  return TokenService(auth, firestore);
});

final tokenBalanceProvider = StreamProvider<int>((ref) {
  final tokenService = ref.watch(tokenServiceProvider);
  return tokenService.tokenBalance;
});

final recentUsageProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(tokenServiceProvider).getRecentUsage();
}); 