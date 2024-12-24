import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../services/firestore_service.dart';
import '../../models/user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final authorizationEndpoint = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');
  final redirectUri = Uri.parse('com.googleusercontent.apps.YOUR_CLIENT_ID:/oauth2redirect');

  Future<void> _signInWithGoogle(BuildContext context) async {
    final clientId = dotenv.env['GOOGLE_CLIENT_ID_WEB']!;
    final authorizationUrl = authorizationEndpoint.replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri.toString(),
      'response_type': 'token id_token',
      'scope': 'https://www.googleapis.com/auth/drive.file email profile',
      'nonce': 'random_nonce',
    });

    html.window.open(authorizationUrl.toString(), "_blank");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _signInWithGoogle(context),
          child: const Text('Sign In with Google'),
        ),
      ),
    );
  }
} 