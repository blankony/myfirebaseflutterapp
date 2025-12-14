// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'login_page.dart'; 
import 'setup/setup_profile_screen.dart'; 
import '../services/app_localizations.dart'; // IMPORT SERVICE LOCALIZATION

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _namaController = TextEditingController(); 
  final TextEditingController _nimController = TextEditingController(); 
  
  final FocusNode _nimFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  String _errorMessage = '';

  bool _isPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;
  bool _isLoading = false; 

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

  Future<void> _signUp() async {
     setState(() { _errorMessage = ''; _isLoading = true; });

    if (!_formKey.currentState!.validate()) {
      setState(() { _isLoading = false; });
      return;
    }

    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (userCredential.user != null) {
        final String nim = _nimController.text.trim();

        final nimQuery = await _firestore
            .collection('users')
            .where('nim', isEqualTo: nim)
            .get();

        if (nimQuery.docs.isNotEmpty) {
          await userCredential.user!.delete();
          // Error ini mungkin spesifik API, tapi kita bisa bungkus jika perlu
          throw FirebaseAuthException(
            code: 'nim-already-in-use', 
            message: 'The NIM $nim is already registered.'
          );
        }

        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'uid': userCredential.user!.uid,
          'email': _emailController.text.trim(),
          'name': _namaController.text.trim(), 
          'nim': nim, 
          'bio': 'Student at PNJ', 
          'createdAt': FieldValue.serverTimestamp(),
          'following': [],
          'followers': [],
        });
        
        if (mounted) {
           Navigator.of(context).pushAndRemoveUntil(
             MaterialPageRoute(builder: (context) => const SetupProfileScreen()),
             (route) => false,
           );
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() { _errorMessage = e.message ?? 'An error occurred'; });
    } catch (e) {
       setState(() { _errorMessage = 'Unknown error occurred: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  // --- VALIDATORS (Updated with Localization) ---
  
  String? _validateName(String? value) {
    // Kita panggil AppLocalizations.of(context) di dalam sini
    var t = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) return t.translate('val_name_empty');
    return null;
  }

  String? _validateNIM(String? value) {
    var t = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) return t.translate('val_nim_empty');
    if (value.length != 10) return t.translate('val_nim_length');
    return null;
  }

  String? _validateEmail(String? value) {
    var t = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) return t.translate('val_email_empty');
    
    String pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(pattern);
    
    if (!regex.hasMatch(value)) {
        return t.translate('val_email_invalid');
    }

    if (!value.endsWith('@stu.pnj.ac.id')) {
        return t.translate('val_email_domain');
    }

    return null;
  }

  String? _validatePassword(String? value) {
    var t = AppLocalizations.of(context)!;
    if (value == null || value.isEmpty) return t.translate('val_pass_empty');
    if (value.length < 6) return t.translate('val_pass_length');
    bool hasLetter = value.contains(RegExp(r'[a-zA-Z]'));
    bool hasNumber = value.contains(RegExp(r'[0-9]'));
    bool hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    if (!hasLetter || !hasNumber || !hasSpecialChar) {
      return t.translate('val_pass_complexity');
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    var t = AppLocalizations.of(context)!;
    if (value == null || value.isEmpty) return t.translate('val_confirm_empty');
    if (value != _passwordController.text) return t.translate('val_pass_mismatch');
    return null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _namaController.dispose();
    _nimController.dispose();
    
    _nimFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    // Inisialisasi localization helper
    var t = AppLocalizations.of(context)!;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.primaryColor),
      ),
      body: Stack(
        children: [
           // --- BACKGROUND BLOBS ---
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

          // --- CONTENT ---
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
                          Text("SAPA", style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: TwitterTheme.blue, letterSpacing: -1.0)),
                          SizedBox(width: 8),
                          Text("PNJ", style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                        ],
                      ),
                      SizedBox(height: 40),

                      Text(
                        t.translate('auth_create_title'), // "Create your account"
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 32),
                      
                      // NAME
                      TextFormField( 
                        controller: _namaController,
                        decoration: InputDecoration(labelText: t.translate('auth_name')), // "Name"
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_nimFocus),
                        validator: _validateName,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      SizedBox(height: 16),
                      
                      // NIM
                      TextFormField( 
                        controller: _nimController,
                        focusNode: _nimFocus,
                        decoration: InputDecoration(labelText: t.translate('auth_nim')), // "NIM"
                        keyboardType: TextInputType.number, 
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: _validateNIM, 
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      SizedBox(height: 16),
                      
                      // EMAIL
                      TextFormField( 
                        controller: _emailController,
                        focusNode: _emailFocus,
                        decoration: InputDecoration(labelText: t.translate('auth_email_hint')), // "Enter email..."
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                        validator: _validateEmail,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      SizedBox(height: 16),
                      
                      // PASSWORD
                      TextFormField( 
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: _isPasswordObscured,
                        decoration: InputDecoration(
                          labelText: t.translate('auth_pass_hint'), // "Enter password"
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
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_confirmPasswordFocus),
                        validator: _validatePassword,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                       SizedBox(height: 16),
                      
                      // CONFIRM PASSWORD
                      TextFormField( 
                        controller: _confirmPasswordController,
                        focusNode: _confirmPasswordFocus,
                        obscureText: _isConfirmPasswordObscured,
                        decoration: InputDecoration(
                          labelText: t.translate('auth_confirm_pass_hint'), // "Confirm password"
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
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _signUp(),
                        validator: _validateConfirmPassword,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      SizedBox(height: 24),
                      
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
                          onPressed: _isLoading ? null : _signUp, 
                          child: _isLoading 
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(t.translate('auth_signup')), // "Sign up"
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
                          Text(t.translate('auth_have_account') + " ", style: TextStyle(color: theme.hintColor)), // "Have an account? "
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).pushReplacement(_createSlideUpRoute(LoginPage()));
                            },
                            child: Text(
                              t.translate('auth_login'), // "Log in"
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
        ],
      ),
    );
  }
}