// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../../auth_gate.dart'; 
import '../../services/overlay_service.dart'; 
import '../../services/app_localizations.dart';

class SetupVerificationScreen extends StatefulWidget {
  const SetupVerificationScreen({super.key});

  @override
  State<SetupVerificationScreen> createState() => _SetupVerificationScreenState();
}

class _SetupVerificationScreenState extends State<SetupVerificationScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isLoading = false;
  bool _isEmailSent = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendVerification() async {
    setState(() { _isLoading = true; });
    final user = FirebaseAuth.instance.currentUser;
    // Localization
    var t = AppLocalizations.of(context)!;
    
    try {
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        setState(() { _isEmailSent = true; });
        if (mounted) {
          OverlayService().showTopNotification(
            context, 
            t.translate('verify_email_sent_toast'), // "Verification email sent!"
            Icons.mark_email_read, 
            (){},
            color: Colors.green
          );
        }
      } else {
         if (mounted) {
           OverlayService().showTopNotification(
             context, 
             t.translate('verify_already_verified'), // "Already verified..."
             Icons.info, 
             (){},
             color: TwitterTheme.blue
           );
         }
      }
    } catch (e) {
      if (mounted) {
        OverlayService().showTopNotification(
          context, 
          "${t.translate('general_error')}: $e", 
          Icons.error, 
          (){},
          color: Colors.red
        );
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _finishSetup() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Localization
    var t = AppLocalizations.of(context)!;
    
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  padding: EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TwitterTheme.blue.withOpacity(0.1),
                  ),
                  child: Icon(Icons.verified_user_outlined, size: 80, color: TwitterTheme.blue),
                ),
              ),
              SizedBox(height: 32),
              Text(
                t.translate('verify_setup_title'), // "Verify your account"
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: TwitterTheme.blue,
                ),
              ),
              SizedBox(height: 16),
              Text(
                t.translate('verify_setup_desc'), // Description text
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
              ),
              SizedBox(height: 40),

              if (!_isEmailSent)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _sendVerification,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: TwitterTheme.blue, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isLoading 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.translate('verify_send_btn'), style: TextStyle(color: TwitterTheme.blue, fontWeight: FontWeight.bold)),
                  ),
                )
              else
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text(t.translate('verify_email_sent_banner'), style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

              SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finishSetup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TwitterTheme.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(t.translate('verify_get_started')), // "Get Started"
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}