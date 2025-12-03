// ignore_for_file: prefer_const_constructors
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../main.dart';
import '../edit_profile_screen.dart';
import '../change_password_screen.dart';
import '../../auth_gate.dart'; 
import '../../services/overlay_service.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class AccountCenterPage extends StatefulWidget {
  const AccountCenterPage({super.key});

  @override
  State<AccountCenterPage> createState() => _AccountCenterPageState();
}

class _AccountCenterPageState extends State<AccountCenterPage> {
  bool _isDeleting = false; 

  Route _createSlideRightRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); 
        const end = Offset.zero;        
        const curve = Curves.easeInOutQuart;
        
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween); 

        return SlideTransition(position: offsetAnimation, child: child);
      },
    );
  }

  // --- Step 1: Prompt Password ---
  Future<void> _promptPasswordForDeletion() async {
    final TextEditingController passwordController = TextEditingController();
    String? errorMessage;
    bool isVerifying = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
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
                  onPressed: isVerifying ? null : () => Navigator.of(builderContext).pop(),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isVerifying ? null : () async {
                    setDialogState(() {
                      isVerifying = true;
                      errorMessage = null;
                    });

                    try {
                      final user = _auth.currentUser;
                      if (user != null && user.email != null) {
                        AuthCredential credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: passwordController.text,
                        );
                        
                        await user.reauthenticateWithCredential(credential);
                        
                        if (builderContext.mounted) {
                          Navigator.of(builderContext).pop(); 
                          
                          if (mounted) {
                            _showFinalDeleteConfirmation(); 
                          }
                        }
                      }
                    } on FirebaseAuthException catch (e) {
                      if (builderContext.mounted) {
                        setDialogState(() {
                          isVerifying = false;
                          if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
                             errorMessage = 'Incorrect password.';
                          } else {
                             errorMessage = 'Error: ${e.message}';
                          }
                        });
                      }
                    } catch (e) {
                       if (builderContext.mounted) {
                         setDialogState(() {
                          isVerifying = false;
                          errorMessage = 'An error occurred.';
                        });
                       }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TwitterTheme.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: isVerifying 
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
  Future<void> _showFinalDeleteConfirmation() async {
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete your account?\n\n'
          'This action is PERMANENT and cannot be undone. All your posts, profile data, and settings will be lost forever.',
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

    if (didConfirm && mounted) {
      _performAccountDeletion();
    }
  }

  // --- Step 3: Execution ---
  Future<void> _performAccountDeletion() async {
    setState(() {
      _isDeleting = true;
    });

    try {
      final user = _auth.currentUser;
      if (user != null) {
        final String uid = user.uid;

        WriteBatch batch = _firestore.batch();
        int batchCount = 0;

        final postsQuery = await _firestore.collection('posts').where('userId', isEqualTo: uid).get();
        
        for (var doc in postsQuery.docs) {
          batch.delete(doc.reference);
          batchCount++;

          if (batchCount >= 450) {
            await batch.commit();
            batch = _firestore.batch();
            batchCount = 0;
          }
        }

        batch.delete(_firestore.collection('users').doc(uid));
        await batch.commit();
        
        await user.delete();
        
        if (mounted) {
          OverlayService().showTopNotification(
            context, 
            "Account deleted successfully.", 
            Icons.delete_forever, 
            (){},
            color: Colors.grey
          );
          
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false; 
        });
        
        OverlayService().showTopNotification(
          context, 
          "Failed to delete account: $e", 
          Icons.error, 
          (){},
          color: Colors.red
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Stack(
      children: [
        Scaffold(
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
                  Navigator.of(context).push(_createSlideRightRoute(EditProfileScreen()));
                },
              ),
              
              // --- PRIVATE ACCOUNT TOGGLE ---
              _PrivacySwitchTile(),
              
              ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Change Password'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
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
                    if (mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: Colors.red),
                title: Text('Delete Account', style: TextStyle(color: Colors.red)),
                subtitle: Text('Permanently delete your account and data'),
                onTap: () => _promptPasswordForDeletion(),
              ),
            ],
          ),
        ),
        
        if (_isDeleting)
          Positioned.fill(
            child: Stack(
              children: [
                Container(color: Colors.black54),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                  child: Container(color: Colors.transparent),
                ),
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                          offset: Offset(0, 10),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 50, 
                          height: 50, 
                          child: CircularProgressIndicator(strokeWidth: 4, color: TwitterTheme.blue)
                        ),
                        SizedBox(height: 24),
                        Text(
                          "Deleting Account",
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Cleaning up your posts and profile data...",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- PRIVACY SWITCH WIDGET ---
class _PrivacySwitchTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final bool isPrivate = data['isPrivate'] ?? false;

        return SwitchListTile(
          secondary: Icon(
            isPrivate ? Icons.lock : Icons.lock_open, 
            color: Theme.of(context).primaryColor
          ),
          title: Text('Private Account'),
          subtitle: Text('Only followers can see your posts and profile details.'),
          value: isPrivate,
          onChanged: (val) async {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'isPrivate': val});
                
            if (context.mounted) {
              OverlayService().showTopNotification(
                context, 
                val ? "Account is now Private" : "Account is now Public", 
                val ? Icons.lock : Icons.public, 
                (){}
              );
            }
          },
        );
      },
    );
  }
}