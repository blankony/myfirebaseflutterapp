// ignore_for_file: prefer_const_constructors
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'register_page.dart';
import '../main.dart'; // Impor untuk TwitterTheme

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              // Ikon di atas
              Align(
                alignment: Alignment.topCenter,
                child: Image.asset('images/app_icon.png', height: 40),
              ),

              Spacer(), // Dorong konten ke tengah dan bawah

              // Teks Judul
              Text(
                "See what's happening in PNJ", // Teks PNJ
                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 30),
              ),
              
              SizedBox(height: 40),

              // Tombol Create Account
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => RegisterPage()),
                    );
                  },
                  child: Text('Create account'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TwitterTheme.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),

              Spacer(), // Dorong footer ke bawah

              // Footer Log in
              RichText(
                text: TextSpan(
                  style: theme.textTheme.titleSmall,
                  children: [
                    TextSpan(text: "Have an account already? "),
                    TextSpan(
                      text: "Log in",
                      style: TextStyle(color: TwitterTheme.blue),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => LoginPage()),
                          );
                        },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}