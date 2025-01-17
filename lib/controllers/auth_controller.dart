import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthController extends StateNotifier<AsyncValue<User?>> {
  final FirebaseAuth _auth;

  AuthController(this._auth) : super(AsyncValue.data(_auth.currentUser)) {
    _auth.authStateChanges().listen((user) {
      if (!mounted) return;
      state = AsyncValue.data(user);
    });
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      // State will be automatically updated by the authStateChanges listener
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<User?>>((ref) {
  return AuthController(FirebaseAuth.instance);
});

// Provider to get the current user synchronously
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authControllerProvider).value;
});

// Provider to check if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
}); 