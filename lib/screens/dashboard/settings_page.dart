// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart'; 
import 'about_page.dart'; 
import '../edit_profile_screen.dart'; // ### IMPOR BARU ###

final FirebaseAuth _auth = FirebaseAuth.instance;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  // --- Fungsi Aksi ---

  void _goToAboutPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AboutPage()),
    );
  }
  
  // ### FUNGSI BARU ###
  void _goToAccountCenter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => EditProfileScreen()),
    );
  }

  void _toggleTheme() {
    themeNotifier.value = themeNotifier.value == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
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
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Account'),
        content: Text('This action is permanent and cannot be undone. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (!didConfirm) return;

    try {
      await user.delete();
      if (context.mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account deleted successfully.'))
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (context.mounted) { 
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please sign in again to delete your account.'))
          );
          await _auth.signOut();
        }
      } else {
        if (context.mounted) { 
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete account: ${e.message}'))
          );
        }
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
          // ### MENU BARU ###
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
          
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, child) {
              return _buildSettingsTile(
                context: context,
                icon: currentMode == ThemeMode.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                title: 'Theme',
                subtitle: currentMode == ThemeMode.dark ? 'Dark' : 'Light',
                onTap: _toggleTheme,
              );
            },
          ),
          
          Divider(),

          _buildSettingsTile(
            context: context,
            icon: Icons.logout,
            title: 'Logout',
            onTap: () => _signOut(context),
          ),

          _buildSettingsTile(
            context: context,
            icon: Icons.delete_forever_outlined,
            title: 'Delete Account',
            color: Colors.red,
            onTap: () => _deleteAccount(context),
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