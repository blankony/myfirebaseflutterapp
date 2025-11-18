// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // Impor untuk InputFormatters
import '../main.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Kunci Global untuk Form
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _namaController = TextEditingController(); 
  final TextEditingController _nimController = TextEditingController(); 
  String _errorMessage = '';

  // State untuk menampilkan/menyembunyikan password
  bool _isPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;

  Future<void> _signUp() async {
     setState(() { _errorMessage = ''; }); // Hapus error server lama

    // 1. Validasi semua form field
    if (!_formKey.currentState!.validate()) {
      // Jika validasi gagal, jangan lakukan apa-apa
      return;
    }

    // 2. Jika validasi berhasil, lanjutkan proses Firebase
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (userCredential.user != null) {
        
        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'uid': userCredential.user!.uid,
          'email': _emailController.text.trim(),
          'name': _namaController.text.trim(), 
          'nim': _nimController.text.trim(), 
          'bio': 'About me...', 
          'createdAt': FieldValue.serverTimestamp(),
          'following': [],
          'followers': [],
        });
        
        await userCredential.user!.sendEmailVerification();
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration successful. Please check your email for verification.')),
          );
          
          Navigator.of(context).pop();
        }
      }
    } on FirebaseAuthException catch (e) {
      // Tampilkan error dari Firebase (misal: email sudah terdaftar)
      setState(() { _errorMessage = e.message ?? 'An error occurred'; });
    } catch (e) {
       setState(() { _errorMessage = 'Unknown error occurred: $e'; });
    }
  }

  // --- Fungsi Validator ---

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name cannot be empty.';
    }
    return null;
  }

  String? _validateNIM(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'NIM cannot be empty.';
    }
    if (value.length != 10) {
      return 'NIM must be exactly 10 digits.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email cannot be empty.';
    }
    // Regex sederhana untuk validasi email
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
    if (value.length < 6) {
      return 'Password must be at least 6 characters long.';
    }
    // Cek kombinasi
    bool hasLetter = value.contains(RegExp(r'[a-zA-Z]'));
    bool hasNumber = value.contains(RegExp(r'[0-9]'));
    bool hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    if (!hasLetter || !hasNumber || !hasSpecialChar) {
      return 'Password must contain letters, numbers, and symbols.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password.';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  // --- Akhir Fungsi Validator ---

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _namaController.dispose();
    _nimController.dispose();
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        // Bungkus dengan Form
        child: Form(
          key: _formKey, // Pasang key
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Create your account",
                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28),
              ),
              SizedBox(height: 32),
              
              TextFormField( // Ganti ke TextFormField
                controller: _namaController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _validateName, // Tambah validator
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              SizedBox(height: 16),
              
              TextFormField( // Ganti ke TextFormField
                controller: _nimController,
                decoration: const InputDecoration(labelText: 'NIM'),
                keyboardType: TextInputType.number, // Keyboard angka
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly, // Hanya izinkan angka
                  LengthLimitingTextInputFormatter(10), // Maksimal 10 angka
                ],
                validator: _validateNIM, // Tambah validator
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              SizedBox(height: 16),
              
              TextFormField( // Ganti ke TextFormField
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Enter email'),
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
              
              TextFormField( // Ganti ke TextFormField
                controller: _confirmPasswordController,
                obscureText: _isConfirmPasswordObscured, // Gunakan state
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  // Tambahkan ikon show/hide
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordObscured ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordObscured = !_isConfirmPasswordObscured;
                      });
                    },
                  ),
                ),
                validator: _validateConfirmPassword, // Tambah validator
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              SizedBox(height: 24),
              
              // Ini untuk error dari server (Firebase)
               if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _signUp, // Fungsi ini sekarang memvalidasi form
                  child: const Text('Sign up'),
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
    );
  }
}