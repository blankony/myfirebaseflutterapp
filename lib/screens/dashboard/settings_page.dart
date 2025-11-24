// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart'; 
import 'about_page.dart'; 
import '../edit_profile_screen.dart';
import 'account_center_page.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _goToAboutPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AboutPage()),
    );
  }
  
  void _goToAccountCenter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AccountCenterPage()),
    );
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
          
          // FIX: Use the Optimized Switch Logic here too
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
          
          Divider(),

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

// ### NEW: Helper Widget for Settings Page ###
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
    return ListTile(
      leading: Icon(
        _isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        color: Theme.of(context).primaryColor
      ),
      title: Text('Theme'),
      subtitle: Text(_isDark ? 'Dark' : 'Light'),
      trailing: Switch(
        value: _isDark,
        onChanged: _handleChange,
      ),
    );
  }
}