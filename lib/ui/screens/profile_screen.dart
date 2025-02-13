import 'package:core_ai_studios/models/user.dart';
import 'package:core_ai_studios/providers/user_provider.dart';
import 'package:core_ai_studios/services/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:core_ai_studios/controllers/auth_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final bool showTokens;
  
  const ProfileScreen({
    Key? key,
    this.showTokens = false,
  }) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late Razorpay _razorpay;
  int _selectedTokenAmount = 0;
  bool _isRazorpayInitialized = false;
  String? _razorpayKey;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tokenSectionKey = GlobalKey();
  final GlobalKey _tokensKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeRazorpay();
    _loadRazorpayKey();
    if (widget.showTokens) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTokenSection();
      });
    }
  }

  Future<void> _loadRazorpayKey() async {
    try {
      await dotenv.load(fileName: ".env");
      setState(() {
        _razorpayKey = dotenv.env['RAZORPAY_KEY'];
      });
    } catch (e) {
      print('Error loading .env file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load payment configuration')),
        );
      }
    }
  }

  Future<void> _initializeRazorpay() async {
    try {
      _razorpay = Razorpay();
      _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      _isRazorpayInitialized = true;
    } catch (e) {
      print('Error initializing Razorpay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize payment system')),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_isRazorpayInitialized) {
      _razorpay.clear();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && mounted) {
      await FirestoreService().updateTokens(user.uid, _selectedTokenAmount);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Payment successful! Tokens updated.")),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Payment failed: \\${response.message}")),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("External wallet selected")),
      );
    }
  }

  void _openCheckout(int amount) async {
    if (!_isRazorpayInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment system not initialized. Please try again.')),
        );
      }
      return;
    }

    if (_razorpayKey == null || _razorpayKey!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment configuration is missing. Please check your .env file.')),
        );
      }
      return;
    }

    var options = {
      'key': _razorpayKey,
      'amount': amount * 100,
      'name': 'Core AI Studios',
      'description': 'Token Purchase',
      'prefill': {
        'contact': '8888888888',
        'email': FirebaseAuth.instance.currentUser?.email ?? ''
      },
      'external': {
        'wallets': ['paytm']
      }
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      print('Error opening Razorpay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open payment. Please try again.')),
        );
      }
    }
  }

  void _scrollToTokenSection() {
    final context = _tokensKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsyncValue = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
      ),
      body: userAsyncValue.when(
        data: (user) {
          if (user == null) return Center(child: Text('User not found'));
          return _buildProfileContent(user);
        },
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildProfileContent(UserModel user) {
    return SingleChildScrollView(
      controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: user.profilePicture != null
                      ? NetworkImage(user.profilePicture!)
                      : null,
                  child: user.profilePicture == null
                ? Icon(Icons.person, size: 50)
                      : null,
                ),
                const SizedBox(height: 16),
          Text(user.name ?? 'User Name', style: TextStyle(fontSize: 20)),
          Text(user.email, style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          _buildTokenSection(user.tokens),
          const SizedBox(height: 32),
          _buildGoogleDriveSection(),
          const SizedBox(height: 32),
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildTokenSection(int tokens) {
    return Container(
      key: _tokensKey,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15.0),
        color: Colors.grey[900],
        border: Border.all(
          color: Colors.amber.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.token_rounded, color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              Text(
                'Tokens: $tokens',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
                ),
                const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showPurchaseOptions(),
              icon: Icon(Icons.add_circle_outline_rounded),
              label: Text('Add More Tokens'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.withOpacity(0.2),
                foregroundColor: Colors.amber,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleDriveSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15.0),
        color: Colors.grey[900],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud, color: Colors.blue),
              const SizedBox(width: 8),
              Text('Google Drive: Connected', style: TextStyle(fontSize: 18)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Read/Write Permissions: Granted',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: OutlinedButton.icon(
        onPressed: () async {
          try {
            // Show loading indicator
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(
                child: CircularProgressIndicator(),
              ),
            );
            
            // Sign out using the auth controller
            await ref.read(authControllerProvider.notifier).signOut();
            
            // Dismiss loading indicator if it's still showing
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          } catch (e) {
            // Dismiss loading indicator if it's showing
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
            
            // Show error message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error signing out: $e')),
              );
            }
          }
        },
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text('Logout', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
          ),
        ),
      ),
    );
  }

  void _showPurchaseOptions() {
    if (!_isRazorpayInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment system is initializing. Please try again.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('100 Tokens for ₹300'),
              onTap: () {
                Navigator.pop(context);
                _selectedTokenAmount = 100;
                _openCheckout(300);
              },
            ),
            ListTile(
              title: Text('200 Tokens for ₹500'),
              onTap: () {
                Navigator.pop(context);
                _selectedTokenAmount = 200;
                _openCheckout(500);
              },
            ),
            ListTile(
              title: Text('500 Tokens for ₹1000'),
              onTap: () {
                Navigator.pop(context);
                _selectedTokenAmount = 500;
                _openCheckout(1000);
              },
            ),
          ],
        );
      },
    );
  }
}
