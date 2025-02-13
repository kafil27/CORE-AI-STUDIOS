import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/firestore_service.dart';
import '../../models/user.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _googleSignIn = GoogleSignIn(
        clientId: '461974819621-h04kt8h0qbo6lfsd4k680shlinjrvtjv.apps.googleusercontent.com',
        scopes: [
          'email',
          'https://www.googleapis.com/auth/drive.file',
          'profile',
        ],
      );
    } else {
      _googleSignIn = GoogleSignIn(
        scopes: [
          'email',
          'https://www.googleapis.com/auth/drive.file',
          'profile',
        ],
      );
    }
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Signing in...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );

      // Attempt Google Sign In
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) {
          Navigator.pop(context); // Dismiss loading
        }
        return;
      }

      try {
        // Get Google Auth credentials
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        // Sign in to Firebase
        final UserCredential userCredential = 
            await FirebaseAuth.instance.signInWithCredential(credential);
        final User? user = userCredential.user;

        if (user != null) {
          // Check if user exists in Firestore
          final docSnapshot = await _firestoreService.getUserById(user.uid);

          if (docSnapshot == null) {
            // Create new user if doesn't exist, using Firebase user data as fallback
            final newUser = UserModel(
              uid: user.uid,
              email: user.email ?? '',
              name: user.displayName ?? 'User',
              profilePicture: user.photoURL ?? '',
              tokens: 0,
              signUpDate: DateTime.now(),
            );
            
            await _firestoreService.createUser(newUser);
          }

          // Dismiss loading and navigate
          if (mounted) {
            Navigator.pop(context); // Dismiss loading
          }
        }
      } catch (authError) {
        print('Auth error: $authError');
        if (mounted) {
          Navigator.pop(context); // Dismiss loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              width: MediaQuery.of(context).size.width * 0.9,
              backgroundColor: Colors.red[900],
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Authentication failed. Please try again.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              duration: Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _signInWithGoogle(context),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Error during Google sign in: $e');
      
      // Dismiss loading if showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Check if it's a People API error
      if (e.toString().contains('People API has not been used')) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text(
                'API Configuration Required',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The Google People API needs to be enabled for this application.',
                    style: TextStyle(color: Colors.grey[300]),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Please follow these steps:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Visit the Google Cloud Console\n2. Enable the People API\n3. Wait a few minutes\n4. Try signing in again',
                    style: TextStyle(color: Colors.grey[300]),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    html.window.open(
                      'https://console.developers.google.com/apis/api/people.googleapis.com/overview?project=461974819621',
                      '_blank'
                    );
                  },
                  child: Text(
                    'Open Console',
                    style: TextStyle(color: Theme.of(context).primaryColor),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _signInWithGoogle(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: Text('Try Again'),
                ),
              ],
            ),
          );
        }
      } else {
        // Show generic error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              width: MediaQuery.of(context).size.width * 0.9,
              backgroundColor: Colors.red[900],
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Failed to sign in with Google. Please try again.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              Colors.grey[900]!,
              Colors.black87,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo/Image
              Container(
                height: 120,
                width: 120,
                margin: EdgeInsets.only(bottom: 20),
                child: Image.asset(
                  'assets/bot_image.png',
                  fit: BoxFit.contain,
                ),
              ),
              
              // Welcome Text
              Text(
                'Welcome to',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white70,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Core AI Studios',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 40),
              
              // Google Sign In Button
              Container(
                width: 300,
                child: ElevatedButton.icon(
                  onPressed: () => _signInWithGoogle(context),
                  icon: Image.asset(
                    'assets/google_logo.png',
                    height: 24,
                    width: 24,
                  ),
                  label: Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 