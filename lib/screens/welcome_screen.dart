// ignore_for_file: prefer_const_constructors
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'register_page.dart';
import '../main.dart'; 

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  // Helper for the "Fly In From Bottom" Page Transition
  Route _createSlideUpRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); // Start from bottom
        const end = Offset.zero;        // End at center
        const curve = Curves.easeInOutQuart;

        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween);

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // --- DECORATIVE BACKGROUND ELEMENTS ---
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Center(
                    child: Image.asset('images/app_icon.png', height: 40),
                  ),

                  Spacer(flex: 2), 

                  Text(
                    "SAPA", 
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 72, 
                      fontWeight: FontWeight.w900,
                      color: TwitterTheme.blue,
                      letterSpacing: -2.0,
                      height: 0.9,
                    ),
                  ),
                  Text(
                    "PNJ", 
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 72, 
                      fontWeight: FontWeight.w900,
                      color: theme.textTheme.bodyLarge?.color,
                      letterSpacing: -2.0,
                      height: 0.9,
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  Container(
                    padding: EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: TwitterTheme.blue, width: 4))
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Text(
                        "Sarana Pengguna\nAplikasi Politeknik\nNegeri Jakarta",
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  
                  Spacer(flex: 3), 

                  Text(
                    "Join the community today.",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Use custom slide-up route
                        Navigator.of(context).push(_createSlideUpRoute(RegisterPage()));
                      },
                      child: Text('Create account'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TwitterTheme.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 18),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16), 
                        ),
                        textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  SizedBox(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
                        children: [
                          TextSpan(text: "Have an account? "),
                          TextSpan(
                            text: "Log in",
                            style: TextStyle(
                              color: TwitterTheme.blue,
                              fontWeight: FontWeight.bold,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                // Use custom slide-up route
                                Navigator.of(context).push(_createSlideUpRoute(LoginPage()));
                              },
                          ),
                        ],
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