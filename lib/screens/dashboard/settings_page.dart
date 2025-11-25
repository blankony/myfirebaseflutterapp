// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../main.dart'; 
import 'about_page.dart'; 
import '../edit_profile_screen.dart';
import 'account_center_page.dart'; 
import '../../services/notification_prefs_service.dart'; // IMPORTED

final FirebaseAuth _auth = FirebaseAuth.instance;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  
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


  void _goToAboutPage(BuildContext context) {
    Navigator.of(context).push(_createSlideRightRoute(AboutPage()));
  }
  
  void _goToAccountCenter(BuildContext context) {
    // When opened from Settings, it should be Slide Right.
    Navigator.of(context).push(_createSlideRightRoute(AccountCenterPage()));
  }

  Future<void> _signOut(BuildContext context) async {
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Sign Out')),
        ],
      ),
    ) ?? false;

    if (didConfirm) {
      await _auth.signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSettingsTile(
            context: context,
            icon: Icons.account_circle_outlined,
            title: 'Account Center',
            onTap: () => _goToAccountCenter(context),
          ),
          
          _buildSettingsTile(
            context: context,
            icon: Icons.info_outline,
            title: 'About Us',
            onTap: () => _goToAboutPage(context),
          ),
          
          // Theme Switch
          _OptimizedThemeTile(),

          ValueListenableBuilder<bool>(
            valueListenable: hapticNotifier,
            builder: (context, isHapticOn, child) {
              return SwitchListTile(
                secondary: Icon(Icons.vibration, color: Theme.of(context).primaryColor),
                title: Text('Haptic Feedback'),
                value: isHapticOn,
                onChanged: (value) {
                  hapticNotifier.value = value;
                },
              );
            },
          ),
          
          // --- NEW NOTIFICATION SETTINGS START ---
          Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Notifications",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: TwitterTheme.blue, fontWeight: FontWeight.bold
              ),
            ),
          ),
          
          // Master Switch for All Notifications
          ValueListenableBuilder<bool>(
            valueListenable: notificationPrefs.allNotificationsEnabled,
            builder: (context, isEnabled, child) {
              return SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined, color: Theme.of(context).primaryColor),
                title: Text('Allow Notifications'),
                subtitle: Text('Master switch for all app notifications'),
                value: isEnabled,
                onChanged: (value) {
                  notificationPrefs.setAllNotifications(value);
                },
              );
            },
          ),

          // Heads-up (Overlay) Switch
          ValueListenableBuilder<bool>(
            valueListenable: notificationPrefs.allNotificationsEnabled,
            builder: (context, allEnabled, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: notificationPrefs.headsUpEnabled,
                builder: (context, headsUpEnabled, child) {
                  return SwitchListTile(
                    // Disable this switch if the master switch is off
                    onChanged: allEnabled ? (value) {
                       notificationPrefs.setHeadsUp(value);
                    } : null,
                    secondary: Icon(Icons.view_day_outlined, color: allEnabled ? Theme.of(context).primaryColor : Theme.of(context).disabledColor),
                    title: Text('Heads-up Popups'),
                    subtitle: Text('Show hovering overlay at the top of screen'),
                    value: allEnabled && headsUpEnabled,
                  );
                },
              );
            },
          ),

          // Clear History Button
          ListTile(
            leading: Icon(Icons.cleaning_services_outlined, color: Colors.red),
            title: Text('Clear Notification History', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Clear History?'),
                  content: Text('This will delete all past notifications permanently.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancel")),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Clear", style: TextStyle(color: Colors.red))),
                  ],
                ),
              ) ?? false;

              if (confirm) {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final batch = FirebaseFirestore.instance.batch();
                  final snapshot = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('notifications')
                      .get();
                  for (var doc in snapshot.docs) {
                    batch.delete(doc.reference);
                  }
                  await batch.commit();
                  if (context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("History cleared.")));
                  }
                }
              }
            },
          ),
          Divider(),
          // --- NEW NOTIFICATION SETTINGS END ---

          _buildSettingsTile(
            context: context,
            icon: Icons.logout,
            title: 'Logout',
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final titleColor = color ?? Theme.of(context).textTheme.bodyLarge?.color;
    final iconColor = color ?? Theme.of(context).primaryColor;

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(color: titleColor)),
      subtitle: subtitle != null ? Text(subtitle) : null,
      onTap: onTap,
    );
  }
}

// ### NEW: Helper Widget for Settings Page (with dynamic subtitle) ###
class _OptimizedThemeTile extends StatefulWidget {
  @override
  State<_OptimizedThemeTile> createState() => _OptimizedThemeTileState();
}

class _OptimizedThemeTileState extends State<_OptimizedThemeTile> {
  late bool _isDark;

  @override
  void initState() {
    super.initState();
    _isDark = themeNotifier.value == ThemeMode.dark;
  }

  void _handleChange(bool value) async {
    setState(() {
      _isDark = value;
    });
    await Future.delayed(Duration(milliseconds: 300));
    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
  }

  @override
  Widget build(BuildContext context) {
    final subtitleText = _isDark ? 'Switch to Light' : 'Switch to Dark';
    
    return ListTile(
      leading: Icon(
        _isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        color: Theme.of(context).primaryColor
      ),
      title: Text('Theme'),
      subtitle: Text(subtitleText),
      trailing: Switch(
        value: _isDark,
        onChanged: _handleChange,
      ),
    );
  }
}