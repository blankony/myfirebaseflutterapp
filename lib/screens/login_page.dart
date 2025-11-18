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
  // Kunci Global untuk Form
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false; 

  // State untuk menampilkan/menyembunyikan password
  bool _isPasswordObscured = true;

  Future<void> _signIn() async {
    if (_isLoading) return; 

    // 1. Validasi form
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
        // Navigasi atau aksi setelah login berhasil
        // Jika Anda menggunakan AuthGate, pop() mungkin tidak diperlukan
        // tergantung alur Anda.
        // Untuk amannya, kita bisa hapus pop() jika AuthGate menangani
        // navigasi global.
        
        // Jika login_page muncul di atas AuthGate/DecisionGate,
        // maka pop() diperlukan.
        Navigator.of(context).pop();
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

  // --- Fungsi Validator ---
  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email cannot be empty.';
    }
    String pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(pattern);
    if (!regex.hasMatch(value)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password cannot be empty.';
    }
    return null;
  }
  // --- Akhir Fungsi Validator ---

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
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            // Bungkus dengan Form
            child: Form(
              key: _formKey, // Pasang key
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Sign in to your account",
                    style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28),
                  ),
                  SizedBox(height: 32),
                  
                  TextFormField( // Ganti ke TextFormField
                    controller: _emailController,
                    decoration: InputDecoration(labelText: 'Enter email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail, // Tambah validator
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  SizedBox(height: 16),
                  
                  TextFormField( // Ganti ke TextFormField
                    controller: _passwordController,
                    obscureText: _isPasswordObscured, // Gunakan state
                    decoration: InputDecoration(
                      labelText: 'Enter password',
                      // Tambahkan ikon show/hide
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
                    validator: _validatePassword, // Tambah validator
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
                      onPressed: _signIn, // Fungsi ini sekarang memvalidasi form
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