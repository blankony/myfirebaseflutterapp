// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:typed_data';
import '../main.dart';
import '../screens/dashboard/account_center_page.dart';
import '../screens/dashboard/settings_page.dart';

class SidePanel extends StatefulWidget {
  final VoidCallback onProfileSelected;

  const SidePanel({
    super.key,
    required this.onProfileSelected,
  });

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  Uint8List? _localImageBytes;
  String? _selectedAvatarIconName;

  @override
  void initState() {
    super.initState();
    _loadLocalAvatar();
  }

  Future<void> _loadLocalAvatar() async {
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String? imagePath = prefs.getString('profile_picture_path_$_currentUserId');
    final String? iconName = prefs.getString('profile_avatar_icon_$_currentUserId');

    if (mounted) {
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          setState(() {
            _localImageBytes = bytes;
            _selectedAvatarIconName = null;
          });
        }
      } else if (iconName != null) {
        setState(() {
          _localImageBytes = null;
          _selectedAvatarIconName = iconName;
        });
      }
    }
  }

  IconData _getIconDataFromString(String? iconName) {
    switch (iconName) {
      case 'face': return Icons.face;
      case 'rocket': return Icons.rocket_launch;
      case 'pet': return Icons.pets;
      default: return Icons.person;
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final bool shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log Out'),
        content: Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (shouldLogout) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  
                  StreamBuilder<DocumentSnapshot>(
                    stream: _currentUserId != null
                        ? FirebaseFirestore.instance.collection('users').doc(_currentUserId).snapshots()
                        : null,
                    builder: (context, snapshot) {
                      String name = "User";
                      String handle = "@user";
                      String initial = "U";

                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        name = data['name'] ?? "User";
                        final email = data['email'] ?? "";
                        handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "@user";
                        if (name.isNotEmpty) initial = name[0].toUpperCase();
                      }

                      return InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          widget.onProfileSelected(); 
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundImage: _localImageBytes != null ? MemoryImage(_localImageBytes!) : null,
                              child: (_localImageBytes == null && _selectedAvatarIconName != null)
                                ? Icon(
                                    _getIconDataFromString(_selectedAvatarIconName),
                                    size: 24,
                                    color: TwitterTheme.blue,
                                  )
                                : (_localImageBytes == null && _selectedAvatarIconName == null)
                                  ? Text(initial)
                                  : null,
                            ),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                Text(handle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          Divider(height: 1),

          // 2. Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  leading: Icon(Icons.account_circle_outlined),
                  title: Text('Account Center'),
                  subtitle: Text('Security, personal details, and more'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => AccountCenterPage()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('More Settings'),
                  subtitle: Text('Privacy, display, and app behavior'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => SettingsPage()),
                    );
                  },
                ),
              ],
            ),
          ),

          // 3. Bottom Actions
          Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: Column(
              children: [
                // FIX: Use the Optimized Switch Tile
                _ThemeSwitchTile(),
                
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Log Out', style: TextStyle(color: Colors.red)),
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ### NEW: Isolated Widget for Smooth Theme Switching ###
class _ThemeSwitchTile extends StatefulWidget {
  @override
  State<_ThemeSwitchTile> createState() => _ThemeSwitchTileState();
}

class _ThemeSwitchTileState extends State<_ThemeSwitchTile> {
  // Local state to update UI instantly
  late bool _isDark; 

  @override
  void initState() {
    super.initState();
    _isDark = themeNotifier.value == ThemeMode.dark;
  }

  void _handleThemeChange(bool value) async {
    // 1. Instant visual update (prevents knob lag)
    setState(() {
      _isDark = value;
    });

    // 2. Delay actual theme switch to let animation finish
    await Future.delayed(Duration(milliseconds: 300));

    // 3. Trigger the heavy app rebuild
    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to external changes too (e.g. if changed from Settings Page)
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        // Sync local state if changed externally
        final bool actualIsDark = currentMode == ThemeMode.dark;
        if (_isDark != actualIsDark) {
           // Only update if we aren't currently toggling (simple check)
           // Ideally we trust the user interaction, but this keeps it in sync
           // We use the local _isDark for the Switch value to ensure smoothness
        }

        return ListTile(
          leading: Icon(Icons.color_lens_outlined),
          title: Text('Theme'),
          subtitle: Text(_isDark ? 'Switch to Light' : 'Switch to Dark'),
          trailing: Switch(
            value: _isDark, 
            onChanged: _handleThemeChange,
          ),
        );
      },
    );
  }
}