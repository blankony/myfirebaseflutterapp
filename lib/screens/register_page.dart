// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _namaController = TextEditingController(); 
  final TextEditingController _nimController = TextEditingController(); 
  String _errorMessage = '';

  Future<void> _signUp() async {
     setState(() { _errorMessage = ''; });

    if (_namaController.text.isEmpty) {
       setState(() { _errorMessage = 'Name cannot be empty.'; });
       return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
       setState(() { _errorMessage = 'Passwords do not match.'; });
       return;
    }
    if (_namaController.text.isEmpty || _nimController.text.isEmpty) { 
       setState(() { _errorMessage = 'Name and NIM cannot be empty.'; });
       return;
    }

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
        });
        
        await userCredential.user!.sendEmailVerification();
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration successful. Please check your email for verification.')),
          );
          
          // ### PERBAIKAN DI SINI ###
          // Tutup halaman ini untuk menampilkan AuthGate (layar verifikasi)
          Navigator.of(context).pop();
          // ### AKHIR PERBAIKAN ###
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() { _errorMessage = e.message ?? 'An error occurred'; });
    } catch (e) {
       setState(() { _errorMessage = 'Unknown error occurred: $e'; });
    }
  }

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Create your account",
              style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28),
            ),
            SizedBox(height: 32),
            TextField( 
              controller: _namaController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            SizedBox(height: 16),
            TextField( 
              controller: _nimController,
              decoration: const InputDecoration(labelText: 'NIM'),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Enter email'),
              keyboardType: TextInputType.emailAddress,
            ),
            SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Enter password'),
              obscureText: true,
            ),
             SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              obscureText: true,
            ),
            SizedBox(height: 24),
             if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _signUp,
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
    );
  }
}