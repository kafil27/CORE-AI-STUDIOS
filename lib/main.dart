import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'ui/screens/login_screen_mobile.dart';
import 'ui/screens/home_screen.dart'; // Import your home screen
import 'ui/screens/profile_screen.dart';
import 'package:core_ai_studios/controllers/auth_controller.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set full screen mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await dotenv.load(fileName: ".env");
  await NotificationService.initialize();
  runApp(ProviderScope(child: MyApp()));
}

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Core AI Studios',
      theme: ThemeData.light(),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          color: Colors.black,
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
        ),
        colorScheme: ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.tealAccent,
        ),
      ),
      themeMode: themeMode,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/profile') {
          return MaterialPageRoute(
            builder: (context) => ProfileScreen(
              showTokens: settings.arguments == 'showTokens',
            ),
            settings: settings,
          );
        }
        // Add other routes as needed
        return null;
      },
      routes: {
        '/': (context) => AuthWrapper(),
        '/login': (context) => LoginScreen(),
        '/home': (context) => HomeScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authControllerProvider).when(
      data: (user) {
        if (user == null) {
          return LoginScreen();
        }
        return HomeScreen();
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => Material(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Authentication Error: $error'),
              ElevatedButton(
                onPressed: () {
                  ref.refresh(authControllerProvider);
                },
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

void showErrorDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Error'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('OK'),
        ),
      ],
    ),
  );
}
