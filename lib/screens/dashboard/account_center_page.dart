// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../main.dart';
import '../edit_profile_screen.dart';
import '../change_password_screen.dart';
import '../../auth_gate.dart'; 
import '../../services/overlay_service.dart';
import '../ktm_verification_screen.dart'; 
import '../../services/app_localizations.dart'; // REQUIRED IMPORT

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class AccountCenterPage extends StatefulWidget {
  const AccountCenterPage({super.key});

  @override
  State<AccountCenterPage> createState() => _AccountCenterPageState();
}

class _AccountCenterPageState extends State<AccountCenterPage> {
  bool _isDeleting = false; 
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _refreshUser();
  }

  /// Forces a reload of the Firebase User to get the latest emailVerified status
  Future<void> _refreshUser() async {
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      await _currentUser!.reload();
      setState(() {
        // Update local reference after reload
        _currentUser = _auth.currentUser;
      });
    }
  }

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

  Future<void> _promptPasswordForDeletion() async {
    final TextEditingController passwordController = TextEditingController();
    String? errorMessage;
    bool isVerifying = false;
    var t = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Text(t.translate('account_verify_pass_title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.translate('account_verify_pass_desc')),
                  SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: t.translate('auth_password'),
                      errorText: errorMessage,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.of(builderContext).pop(),
                  child: Text(t.translate('general_cancel')),
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
                             errorMessage = t.translate('error_invalid_credential');
                          } else {
                             errorMessage = 'Error: ${e.message}';
                          }
                        });
                      }
                    } catch (e) {
                       if (builderContext.mounted) {
                         setDialogState(() {
                          isVerifying = false;
                          errorMessage = t.translate('general_error');
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
                    : Text(t.translate('account_verify_btn')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showFinalDeleteConfirmation() async {
    var t = AppLocalizations.of(context)!;
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.translate('account_delete_title')),
        content: Text(t.translate('account_delete_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.translate('general_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(t.translate('account_delete_title')),
          ),
        ],
      ),
    ) ?? false;

    if (didConfirm && mounted) {
      _performAccountDeletion();
    }
  }

  Future<void> _performAccountDeletion() async {
    setState(() {
      _isDeleting = true;
    });
    var t = AppLocalizations.of(context)!;

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
            t.translate('account_deleted'), 
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
          "${t.translate('account_delete_fail')}: $e", 
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
    final user = _auth.currentUser; // Use fresh instance
    final bool isEmailVerified = user?.emailVerified ?? false;
    var t = AppLocalizations.of(context)!;
    
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(t.translate('settings_account')), // "Account Center"
          ),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  t.translate('account_verif_status'),
                  style: theme.textTheme.titleMedium?.copyWith(color: TwitterTheme.blue, fontWeight: FontWeight.bold),
                ),
              ),

              // --- 1. EMAIL VERIFICATION ---
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isEmailVerified ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle
                  ),
                  child: Icon(
                    isEmailVerified ? Icons.email : Icons.mark_email_unread, 
                    color: isEmailVerified ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                ),
                title: Text(t.translate('profile_verify_email')),
                subtitle: Text(isEmailVerified ? t.translate('account_verified') : t.translate('account_action_req')),
                trailing: isEmailVerified 
                  ? Icon(Icons.check_circle, color: Colors.green)
                  : TextButton(
                      child: Text(t.translate('general_verify')),
                      onPressed: () async {
                        try {
                          await user?.sendEmailVerification();
                          OverlayService().showTopNotification(context, t.translate('profile_verify_sent'), Icons.email, (){});
                        } catch (e) {
                          OverlayService().showTopNotification(context, t.translate('profile_verify_wait'), Icons.timer, (){}, color: Colors.orange);
                        }
                      },
                    ),
              ),

              // --- 2. KTM VERIFICATION (Only shows if Email Verified) ---
              if (isEmailVerified)
                StreamBuilder<DocumentSnapshot>(
                  stream: _firestore.collection('users').doc(user!.uid).snapshots(),
                  builder: (context, snapshot) {
                    String status = 'none';
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data() as Map<String, dynamic>;
                      status = data['verificationStatus'] ?? 'none';
                    }

                    String title = t.translate('account_ktm');
                    String subtitle = t.translate('account_ktm_desc');
                    IconData icon = Icons.badge_outlined;
                    Color color = Colors.grey;
                    Widget? trailing;

                    if (status == 'verified') {
                      subtitle = t.translate('account_ktm_verified');
                      color = Colors.green;
                      icon = Icons.verified_user;
                      trailing = Icon(Icons.check_circle, color: Colors.green);
                    } else if (status == 'pending') {
                      subtitle = t.translate('account_ktm_review');
                      color = Colors.orange;
                      icon = Icons.hourglass_top;
                      trailing = Text(t.translate('profile_verify_pending'), style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold));
                    } else if (status == 'rejected') {
                      subtitle = t.translate('account_ktm_rejected');
                      color = Colors.red;
                      icon = Icons.error_outline;
                      trailing = Icon(Icons.arrow_forward_ios, size: 16);
                    } else {
                      // None
                      trailing = Icon(Icons.arrow_forward_ios, size: 16);
                    }

                    return ListTile(
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: trailing,
                      onTap: (status == 'verified' || status == 'pending') 
                        ? null 
                        : () => Navigator.push(context, MaterialPageRoute(builder: (_) => KtmVerificationScreen())),
                    );
                  },
                ),

              Divider(height: 32),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  t.translate('account_profile_header'),
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold),
                ),
              ),
              
              ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text(t.translate('profile_edit')),
                subtitle: Text(t.translate('account_edit_desc')),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.of(context).push(_createSlideRightRoute(EditProfileScreen()));
                },
              ),
              
              _PrivacySwitchTile(),
              
              ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text(t.translate('edit_change_password')),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.of(context).push(_createSlideRightRoute(ChangePasswordScreen()));
                },
              ),
              
              Divider(height: 32),
              
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  t.translate('account_danger'),
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(Icons.logout, color: theme.iconTheme.color),
                title: Text(t.translate('settings_logout')),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(t.translate('settings_logout')),
                      content: Text(t.translate('settings_logout_confirm')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.translate('general_cancel'))),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.translate('settings_logout'), style: TextStyle(color: Colors.red))),
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
                title: Text(t.translate('account_delete_title'), style: TextStyle(color: Colors.red)),
                subtitle: Text(t.translate('account_delete_subtitle')),
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
                          t.translate('account_deleting'),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          t.translate('account_cleaning'),
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

class _PrivacySwitchTile extends StatefulWidget {
  @override
  State<_PrivacySwitchTile> createState() => _PrivacySwitchTileState();
}

class _PrivacySwitchTileState extends State<_PrivacySwitchTile> {
  bool _isUpdating = false;

  Future<void> _togglePrivacy(BuildContext context, bool isCurrentlyPrivate) async {
    var t = AppLocalizations.of(context)!;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCurrentlyPrivate ? t.translate('account_switch_public') : t.translate('account_switch_private')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isCurrentlyPrivate 
              ? t.translate('account_public_mean') 
              : t.translate('account_private_mean')),
            SizedBox(height: 8),
            _buildBulletPoint(isCurrentlyPrivate 
              ? t.translate('account_public_bullet1') 
              : t.translate('account_private_bullet1')),
            _buildBulletPoint(isCurrentlyPrivate 
              ? t.translate('account_public_bullet2') 
              : t.translate('account_private_bullet2')),
            SizedBox(height: 8),
            Text(
              t.translate('account_privacy_note'),
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.translate('general_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: TwitterTheme.blue,
              foregroundColor: Colors.white,
            ),
            child: Text(t.translate('general_confirm')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        setState(() => _isUpdating = true);
        
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'isPrivate': !isCurrentlyPrivate});

          final batch = FirebaseFirestore.instance.batch();
          final postsQuery = await FirebaseFirestore.instance
              .collection('posts')
              .where('userId', isEqualTo: user.uid)
              .get();

          final String targetNewVisibility = isCurrentlyPrivate ? 'public' : 'followers';

          int batchCount = 0;
          for (var doc in postsQuery.docs) {
            final data = doc.data();
            final currentVis = data['visibility'] ?? 'public'; 

            if (currentVis != 'private') {
              if (currentVis != targetNewVisibility) {
                batch.update(doc.reference, {'visibility': targetNewVisibility});
                batchCount++;
              }
            }
            
            if (batchCount >= 450) {
              await batch.commit();
            }
          }
          
          if (batchCount > 0) {
            await batch.commit();
          }

          if (context.mounted) {
            OverlayService().showTopNotification(
              context, 
              !isCurrentlyPrivate ? t.translate('account_privacy_now_private') : t.translate('account_privacy_now_public'), 
              !isCurrentlyPrivate ? Icons.lock : Icons.public, 
              (){}
            );
          }
        } catch (e) {
          if (context.mounted) {
            OverlayService().showTopNotification(
              context, t.translate('account_privacy_update_fail'), Icons.error, (){}, color: Colors.red
            );
          }
        } finally {
          if (mounted) setState(() => _isUpdating = false);
        }
      }
    }
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return SizedBox.shrink();
    var t = AppLocalizations.of(context)!;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final bool isPrivate = data['isPrivate'] ?? false;

        return SwitchListTile(
          secondary: _isUpdating 
            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                isPrivate ? Icons.lock : Icons.lock_open, 
                color: Theme.of(context).primaryColor
              ),
          title: Text(t.translate('account_private_title')),
          subtitle: Text(t.translate('account_private_subtitle')),
          value: isPrivate,
          onChanged: _isUpdating ? null : (_) => _togglePrivacy(context, isPrivate),
        );
      },
    );
  }
}