// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'dart:async';
import '../auth_gate.dart'; 
import '../main.dart'; // For TwitterTheme

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // 1. Setup Animation Controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Logo Bounce Effect
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    // Text Fade In
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller, 
        curve: Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    // Text Slide Up
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller, 
        curve: Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    // Start Animation
    _controller.forward();

    // 2. Navigate to AuthGate after delay
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const AuthGate(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // --- DECORATIVE BACKGROUND (Matches Welcome Screen) ---
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TwitterTheme.blue.withOpacity(isDarkMode ? 0.15 : 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: 150,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TwitterTheme.blue.withOpacity(isDarkMode ? 0.1 : 0.05),
              ),
            ),
          ),

          // --- MAIN CONTENT ---
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. Animated Logo
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TwitterTheme.blue.withOpacity(0.1),
                      boxShadow: [
                        BoxShadow(
                          color: TwitterTheme.blue.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ]
                    ),
                    child: Image.asset('images/app_icon.png', height: 100, width: 100),
                  ),
                ),
                
                SizedBox(height: 40),

                // 2. Animated Text
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Text(
                          "SAPA", 
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 48, 
                            fontWeight: FontWeight.w900,
                            color: TwitterTheme.blue,
                            letterSpacing: -1.0,
                            height: 0.9,
                          ),
                        ),
                        Text(
                          "PNJ", 
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 48, 
                            fontWeight: FontWeight.w900,
                            color: theme.textTheme.bodyLarge?.color,
                            letterSpacing: -1.0,
                            height: 0.9,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Sarana Pengguna Aplikasi\nPoliteknik Negeri Jakarta",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.hintColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}