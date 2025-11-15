// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'decision_gate.dart'; 
import 'screens/welcome_screen.dart'; // Impor WelcomeScreen BARU

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData) {
          return const DecisionGate();
        }
        
        // PERUBAHAN DI SINI:
        // Arahkan ke WelcomeScreen, bukan LoginOrRegisterPage
        return const WelcomeScreen();
      },
    );
  }
}