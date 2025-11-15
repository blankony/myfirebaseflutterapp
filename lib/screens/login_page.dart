// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'forgot_password_screen.dart'; 
import '../main.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false; // State untuk loading

  Future<void> _signIn() async {
    // Jangan lakukan apa-apa jika sedang loading
    if (_isLoading) return; 

    setState(() { 
      _isLoading = true; // Mulai loading
      _errorMessage = ''; 
    });

    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      // Terjemahkan kode error Firebase ke pesan yang ramah
      switch (e.code) {
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          _errorMessage = 'Incorrect email or password. Please try again.';
          break;
        case 'invalid-email':
          _errorMessage = 'The email address is badly formatted.';
          break;
        case 'user-disabled':
          _errorMessage = 'This user account has been disabled.';
          break;
        default:
          _errorMessage = 'An unknown error occurred. Please try again.';
      }
    } catch (e) {
       _errorMessage = 'An unknown error occurred: $e';
    } finally {
      // Pastikan loading berhenti
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset('images/app_icon.png', height: 30),
        centerTitle: true,
      ),
      // Gunakan Stack untuk menempatkan loading indicator di atas
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Sign in to your account",
                  style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28),
                ),
                SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(labelText: 'Enter email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(labelText: 'Enter password'),
                  obscureText: true,
                ),
                SizedBox(height: 16),

                // Tampilkan error jika ada
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, top: 8),
                    child: Center(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () {
                       Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => ForgotPasswordScreen()),
                      );
                    },
                    child: Text('Forgot password?', style: TextStyle(color: TwitterTheme.blue)),
                  ),
                ),
                SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _signIn,
                    child: Text('Login'),
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
              ],
            ),
          ),

          // --- Loading Indicator Overlay ---
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}