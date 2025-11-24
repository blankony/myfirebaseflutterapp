// ignore_for_file: prefer_const_constructors
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../screens/dashboard/account_center_page.dart';
import '../screens/dashboard/settings_page.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;

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

  Future<void> _signOut() async {
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
        // Pop back to the first route (AuthGate -> WelcomeScreen)
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  // Helper for the "Fly In From Bottom" Page Transition
  Route _createSlideUpRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); // Start from bottom
        const end = Offset.zero;        // End at center
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Stack( // Wrap content in Stack for decorative blobs
        children: [
          // --- DECORATIVE BACKGROUND ELEMENTS ---
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
          
          // --- MAIN CONTENT ---
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          
                          // Avatar Defaults
                          int iconId = 0;
                          String? colorHex;

                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data = snapshot.data!.data() as Map<String, dynamic>;
                            name = data['name'] ?? "User";
                            final email = data['email'] ?? "";
                            handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "@user";
                            
                            // Get Avatar Info
                            iconId = data['avatarIconId'] ?? 0;
                            colorHex = data['avatarHex'];
                          }

                          // Universal Avatar Display
                          Widget avatarWidget = CircleAvatar(
                            radius: 24,
                            backgroundColor: AvatarHelper.getColor(colorHex),
                            child: Icon(AvatarHelper.getIcon(iconId), size: 24, color: Colors.white),
                          );

                          return InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              widget.onProfileSelected(); 
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              children: [
                                avatarWidget,
                                SizedBox(width: 12),
                                // FIX: Expanded prevents the Column from pushing off the screen
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name, 
                                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis, // Adds the "..."
                                        maxLines: 1, // Ensures single line
                                      ),
                                      Text(
                                        handle, 
                                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                                        overflow: TextOverflow.ellipsis, // Adds the "..."
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
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
              
              Expanded(child: ListView(children: [
                ListTile(leading: Icon(Icons.account_circle_outlined), title: Text('Account Center'), onTap: () {
                  Navigator.pop(context); 
                  Navigator.of(context).push(_createSlideUpRoute(AccountCenterPage()));
                }),
                ListTile(leading: Icon(Icons.settings_outlined), title: Text('More Settings'), onTap: () {
                  Navigator.pop(context); 
                  Navigator.of(context).push(_createSlideUpRoute(SettingsPage()));
                }),
              ])),
              
              Divider(height: 1),
              Padding(padding: EdgeInsets.all(8), child: Column(children: [
                 _ThemeSwitchTile(),
                 // --- LOGOUT BUTTON MOVED HERE ---
                 ListTile(
                  leading: Icon(Icons.logout, color: Colors.red), 
                  title: Text('Logout', style: TextStyle(color: Colors.red)), 
                  onTap: _signOut,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                ),
                // ------------------------------------
              ]))
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeSwitchTile extends StatefulWidget {
  @override State<_ThemeSwitchTile> createState() => _ThemeSwitchTileState();
}
class _ThemeSwitchTileState extends State<_ThemeSwitchTile> {
  late bool _isDark;
  @override void initState() { 
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
    final theme = Theme.of(context);
    final String subtitleText = _isDark ? 'Switch to Light' : 'Switch to Dark';

    return ListTile(
      leading: Icon(Icons.color_lens_outlined, color: theme.primaryColor), 
      title: Text('Theme'), 
      subtitle: Text(subtitleText), // Dynamic subtitle
      trailing: Switch(
        value: _isDark, 
        onChanged: _handleChange,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    );
  }
}