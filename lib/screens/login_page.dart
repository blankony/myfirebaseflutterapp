// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'forgot_password_screen.dart';
import 'register_page.dart'; 
import '../main.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false; 
  bool _isPasswordObscured = true;

  // Helper for custom transition
  Route _createSlideUpRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeInOutQuart;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  Future<void> _signIn() async {
    if (_isLoading) return; 

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() { 
      _isLoading = true; 
      _errorMessage = ''; 
    });

    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
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
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email cannot be empty.';
    String pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(pattern);
    if (!regex.hasMatch(value)) return 'Enter a valid email address.';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password cannot be empty.';
    return null;
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
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true, // Allow blobs to sit behind AppBar
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.primaryColor),
      ),
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
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 1.0, end: 0.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutQuart,
            builder: (context, double value, child) {
              return Transform.translate(
                offset: Offset(0, value * 200),
                child: Opacity(
                  opacity: 1 - value,
                  child: child,
                ),
              );
            },
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rebranding Header
                      Row(
                        children: [
                          Text(
                            "SAPA", 
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: TwitterTheme.blue,
                              letterSpacing: -1.0,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            "PNJ", 
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.0,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 40),

                      Text(
                        "Sign in to your account",
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 32),
                      
                      TextFormField( 
                        controller: _emailController,
                        decoration: InputDecoration(labelText: 'Enter email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _isPasswordObscured,
                        decoration: InputDecoration(
                          labelText: 'Enter password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordObscured = !_isPasswordObscured;
                              });
                            },
                          ),
                        ),
                        validator: _validatePassword,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      SizedBox(height: 16),

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
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 24),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have an account? ", style: TextStyle(color: theme.hintColor)),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).pushReplacement(_createSlideUpRoute(RegisterPage()));
                            },
                            child: Text(
                              "Create one",
                              style: TextStyle(
                                color: TwitterTheme.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),

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