// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:firebase_core/firebase_core.dart'; - 제거됨
import 'providers/auth_provider.dart' as local_auth;
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/phone_auth_screen.dart';
import 'config/aws_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase - 제거됨
  // await Firebase.initializeApp();
  
  // Initialize AWS configuration
  await _initializeApp();
  
  runApp(const MyApp());
}

Future<void> _initializeApp() async {
  try {
    // Initialize AWS configuration
    AWSConfig.initialize();
    print('Successfully initialized AWS configuration 🎉');
  } catch (e) {
    print('An error occurred initializing app: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => local_auth.CustomAuthProvider()),
      ],
      child: MaterialApp(
        title: '파킨슨 관리 앱',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF2F3DA3)),
          useMaterial3: true,
        ),
        home: const SplashScreen(),
        routes: {
          '/auth': (context) => const AuthWrapper(),
          '/home': (context) => const HomeScreen(),
          '/login': (context) => const LoginScreen(),
          '/phone-auth': (context) => const PhoneAuthScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<local_auth.CustomAuthProvider>(
      builder: (context, authProvider, child) {
        // 로딩 중일 때
        if (authProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('로딩 중...'),
                ],
              ),
            ),
          );
        }

        // 인증 상태에 따라 화면 전환
        if (authProvider.isAuthenticated) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}