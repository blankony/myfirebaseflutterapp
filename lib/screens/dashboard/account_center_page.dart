// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../main.dart';
import '../edit_profile_screen.dart';
import '../change_password_screen.dart';
import '../welcome_screen.dart'; // FIX: Imported WelcomeScreen

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class AccountCenterPage extends StatelessWidget {
  const AccountCenterPage({super.key});

  // Helper for the "Fly In From Right" Page Transition
  Route _createSlideRightRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); // Start from Right
        const end = Offset.zero;        // End at Center
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


  // --- Step 1: Prompt Password ---
  Future<void> _promptPasswordForDeletion(BuildContext context) async {
    final TextEditingController passwordController = TextEditingController();
    String? errorMessage;
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Verify Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Please enter your password to continue.'),
                  SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: errorMessage,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setState(() {
                      isLoading = true;
                      errorMessage = null;
                    });

                    try {
                      final user = _auth.currentUser;
                      if (user != null && user.email != null) {
                        AuthCredential credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: passwordController.text,
                        );
                        
                        // Attempt re-auth
                        await user.reauthenticateWithCredential(credential);
                        
                        // If successful, close this dialog and show the final one
                        if (context.mounted) {
                          Navigator.of(context).pop(); // Close password dialog
                          _showFinalDeleteConfirmation(context); // Show final dialog
                        }
                      }
                    } on FirebaseAuthException catch (e) {
                      setState(() {
                        isLoading = false;
                        if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
                           errorMessage = 'Incorrect password.';
                        } else {
                           errorMessage = 'Error: ${e.message}';
                        }
                      });
                    } catch (e) {
                       setState(() {
                        isLoading = false;
                        errorMessage = 'An error occurred.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TwitterTheme.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading 
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Step 2: Final Confirmation ---
  Future<void> _showFinalDeleteConfirmation(BuildContext context) async {
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete your account?\n\n'
          'This action is PERMANENT and cannot be undone. All your data (posts, profile, settings) will be lost forever.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete Account'),
          ),
        ],
      ),
    ) ?? false;

    if (didConfirm) {
      _performAccountDeletion(context);
    }
  }

  // --- Step 3: Execution ---
  Future<void> _performAccountDeletion(BuildContext context) async {
    // Show blocking loading dialog
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );

    try {
      final user = _auth.currentUser;
      if (user != null) {
        // 1. Delete Firestore Data (User Doc)
        await _firestore.collection('users').doc(user.uid).delete();
        
        // 2. Delete Auth Account
        await user.delete();
        
        if (context.mounted) {
          Navigator.of(context).pop(); // Dismiss loading
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Account deleted successfully.'))
          );
          
          // FIX: Navigate to Welcome Screen instead of Login
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Account Center'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Profile & Security",
              style: theme.textTheme.titleMedium?.copyWith(color: TwitterTheme.blue, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit Profile'),
            subtitle: Text('Change Name, Bio, and Avatar'),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Apply Slide Right Animation
              Navigator.of(context).push(_createSlideRightRoute(EditProfileScreen()));
            },
          ),
          ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Change Password'),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Apply Slide Right Animation
              Navigator.of(context).push(_createSlideRightRoute(ChangePasswordScreen()));
            },
          ),
          
          Divider(height: 32),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Danger Zone",
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.iconTheme.color),
            title: Text('Log Out'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Log Out'),
                  content: Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Log Out", style: TextStyle(color: Colors.red))),
                  ],
                ),
              ) ?? false;

              if(confirm) {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: Text('Delete Account', style: TextStyle(color: Colors.red)),
            subtitle: Text('Permanently delete your account and data'),
            onTap: () => _promptPasswordForDeletion(context),
          ),
        ],
      ),
    );
  }
}