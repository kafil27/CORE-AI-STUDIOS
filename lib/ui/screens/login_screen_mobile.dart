import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../../services/firestore_service.dart';
import '../../models/user.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  late AnimationController _animationController;
  late Animation<double> _floatAnimation;
  bool _agreedToTerms = false;
  bool _isSigningIn = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(
      begin: -10.0,
      end: 10.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    try {
      // Check if all required permissions are already granted
      bool allGranted = true;
      Map<Permission, PermissionStatus> currentStatus = {
        Permission.storage: await Permission.storage.status,
        Permission.manageExternalStorage: await Permission.manageExternalStorage.status,
        Permission.photos: await Permission.photos.status,
        Permission.videos: await Permission.videos.status,
        Permission.audio: await Permission.audio.status,
        Permission.notification: await Permission.notification.status,
        Permission.mediaLibrary: await Permission.mediaLibrary.status,
      };

      currentStatus.forEach((permission, status) {
        if (!status.isGranted) {
          allGranted = false;
        }
      });

      // If all permissions are already granted, return true
      if (allGranted) return true;

      // Request permissions in a single batch
      Map<Permission, PermissionStatus> statuses = await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
        Permission.notification,
        Permission.mediaLibrary,
      ].request();

      List<Permission> deniedPermissions = [];
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          deniedPermissions.add(permission);
        }
      });

      // If no permissions are denied, return true
      if (deniedPermissions.isEmpty) return true;

      // Show dialog only if some permissions are denied
      if (mounted) {
        bool shouldContinue = await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.warning_amber_rounded, 
                            color: Colors.amber,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Permissions Required',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Content
                  Container(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'The following permissions are required:',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.3,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: deniedPermissions.map((permission) => 
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          _getPermissionIcon(permission),
                                          color: Colors.blue[300],
                                          size: 20,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _getPermissionTitle(permission),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              _getPermissionDescription(permission),
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ).toList(),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'These permissions are necessary for core app functionality.',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Actions
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context, false);
                            setState(() => _agreedToTerms = false);
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ),
                        SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context, false);
                            AppSettings.openAppSettings();
                          },
                          child: Text(
                            'Open Settings',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          child: Text(
                            'Continue Anyway',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ) ?? false;

        return shouldContinue;
      }

      return false;
    } catch (e) {
      print('Error requesting permissions: $e');
      return false;
    }
  }

  IconData _getPermissionIcon(Permission permission) {
    switch (permission) {
      case Permission.storage:
      case Permission.manageExternalStorage:
        return Icons.storage;
      case Permission.photos:
        return Icons.perm_media;
      case Permission.videos:
        return Icons.perm_media;
      case Permission.audio:
        return Icons.volume_up;
      case Permission.notification:
        return Icons.notifications;
      case Permission.mediaLibrary:
        return Icons.library_music;
      default:
        return Icons.error_outline;
    }
  }

  String _getPermissionTitle(Permission permission) {
    switch (permission) {
      case Permission.storage:
      case Permission.manageExternalStorage:
        return 'Storage Access';
      case Permission.photos:
        return 'Photo Library';
      case Permission.videos:
        return 'Video Library';
      case Permission.audio:
        return 'Audio Access';
      case Permission.notification:
        return 'Notifications';
      case Permission.mediaLibrary:
        return 'Media Library';
      default:
        return permission.toString().split('.').last;
    }
  }

  String _getPermissionDescription(Permission permission) {
    switch (permission) {
      case Permission.storage:
      case Permission.manageExternalStorage:
        return 'Required to save your generated content';
      case Permission.photos:
        return 'Access to save generated images';
      case Permission.videos:
        return 'Access to save generated videos';
      case Permission.audio:
        return 'For app sound effects and feedback';
      case Permission.notification:
        return 'Updates about your content generation';
      case Permission.mediaLibrary:
        return 'Access to manage generated content';
      default:
        return 'Required for app functionality';
    }
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    if (!_agreedToTerms) return;

    setState(() => _isSigningIn = true);

    try {
      if (!await _requestPermissions()) {
        setState(() => _isSigningIn = false);
        return;
      }

      // Proceed with Google Sign In
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isSigningIn = false);
        return;
      }

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
        final docSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!docSnapshot.exists) {
          final newUser = UserModel(
            uid: user.uid,
            email: user.email ?? '',
            name: user.displayName,
            profilePicture: user.photoURL,
            tokens: 0,
            signUpDate: DateTime.now(),
          );
          
          await _firestoreService.createUser(newUser);
        }
      }
    } catch (e) {
      print('Error during Google sign in: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sign in with Google'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _signInWithGoogle(context),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<void> _showTermsAndConditions() async {
    // Dummy URL for now
    const url = 'https://example.com/terms';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedGradientBox(),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _floatAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _floatAnimation.value),
                        child: Container(
                          height: 120,
                          width: 120,
                          margin: EdgeInsets.only(bottom: 20),
                          child: Image.asset(
                            'assets/bot_image.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  Text(
                    'Login to continue to',
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
                  
                  // Terms and Conditions Checkbox
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Transform.scale(
                          scale: 1.2,
                          child: Checkbox(
                            value: _agreedToTerms,
                            onChanged: (value) {
                              setState(() => _agreedToTerms = value ?? false);
                            },
                            fillColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected)) {
                                  return Colors.blue;
                                }
                                return Colors.grey;
                              },
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(color: Colors.grey[400], fontSize: 14),
                              children: [
                                TextSpan(text: 'I agree to the '),
                                TextSpan(
                                  text: 'Terms and Conditions',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = _showTermsAndConditions,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  
                  // Google Sign In Button
                  AnimatedOpacity(
                    duration: Duration(milliseconds: 300),
                    opacity: _agreedToTerms ? 1.0 : 0.5,
                    child: ElevatedButton.icon(
                      onPressed: _agreedToTerms && !_isSigningIn
                          ? () => _signInWithGoogle(context)
                          : null,
                      icon: _isSigningIn
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                              ),
                            )
                          : Image.asset(
                              'assets/google_logo.png',
                              height: 24,
                              width: 24,
                            ),
                      label: Text(
                        _isSigningIn ? 'Signing in...' : 'Continue with Google',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: _agreedToTerms ? 4 : 0,
                        shadowColor: Colors.black.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedGradientBox extends StatefulWidget {
  @override
  _AnimatedGradientBoxState createState() => _AnimatedGradientBoxState();
}

class _AnimatedGradientBoxState extends State<AnimatedGradientBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  List<Color> colorsList = [
    Colors.black,
    Color(0xFF1a1a1a),
    Colors.blueGrey[900]!,
    Colors.black87,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(
                math.cos(_animation.value),
                math.sin(_animation.value),
              ),
              end: Alignment(
                math.cos(_animation.value + math.pi),
                math.sin(_animation.value + math.pi),
              ),
              colors: colorsList,
              stops: [0.0, 0.33, 0.67, 1.0],
            ),
          ),
        );
      },
    );
  }
} 