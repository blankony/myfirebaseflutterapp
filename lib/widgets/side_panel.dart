// ignore_for_file: prefer_const_constructors
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart'; // IMPORTED
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
      child: StreamBuilder<DocumentSnapshot>(
        stream: _currentUserId != null
            ? FirebaseFirestore.instance.collection('users').doc(_currentUserId).snapshots()
            : null,
        builder: (context, snapshot) {
          String name = "User";
          String handle = "@user";
          
          // Avatar Defaults
          int iconId = 0;
          String? colorHex;
          String? profileImageUrl; 
          String? bannerImageUrl; // NEW

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            name = data['name'] ?? "User";
            final email = data['email'] ?? "";
            handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "@user";
            
            // Get Avatar & Banner Info
            iconId = data['avatarIconId'] ?? 0;
            colorHex = data['avatarHex'];
            profileImageUrl = data['profileImageUrl'];
            bannerImageUrl = data['bannerImageUrl']; // NEW
          }

          // Universal Avatar Display
          Widget avatarWidget = CircleAvatar(
            radius: 28, // Slightly larger for drawer header
            backgroundColor: profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex),
            backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
            child: profileImageUrl == null ?
              Icon(AvatarHelper.getIcon(iconId), size: 28, color: Colors.white)
              : null,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- CUSTOM HEADER WITH BANNER BACKGROUND ---
              SizedBox(
                height: 220, // Height for header area
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. Background Image (Banner)
                    if (bannerImageUrl != null && bannerImageUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: bannerImageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: theme.primaryColor.withOpacity(0.2)),
                        errorWidget: (context, url, error) => Container(color: theme.scaffoldBackgroundColor),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                        ),
                        // Fallback decorative blobs if no banner
                        child: Stack(
                          children: [
                            Positioned(
                              top: -50, right: -50,
                              child: Container(
                                width: 150, height: 150,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withOpacity(0.2)),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 2. Gradient Overlay (For text readability)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.1),
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),

                    // 3. Content (Close Button, Avatar, Text)
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Close Button Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.close, color: Colors.white), // Always white due to overlay
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                            Spacer(),
                            
                            // Clickable Profile Area
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                widget.onProfileSelected(); 
                              },
                              child: Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2), // White border makes it pop
                                    ),
                                    child: avatarWidget,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          name, 
                                          style: theme.textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold, 
                                            color: Colors.white // Always white on banner
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        Text(
                                          handle, 
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: Colors.white70 // Light grey on banner
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              Divider(height: 1, thickness: 1),
              
              Expanded(child: ListView(padding: EdgeInsets.zero, children: [
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
                 // --- LOGOUT BUTTON ---
                 ListTile(
                  leading: Icon(Icons.logout, color: Colors.red), 
                  title: Text('Logout', style: TextStyle(color: Colors.red)), 
                  onTap: _signOut,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                ),
              ]))
            ],
          );
        },
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

    // Wrapped in InkWell or handled by ListTile's onTap to make the whole row clickable
    return ListTile(
      onTap: () => _handleChange(!_isDark), // Toggle on row click
      leading: Icon(Icons.color_lens_outlined, color: theme.primaryColor), 
      title: Text('Theme'), 
      subtitle: Text(subtitleText), 
      trailing: Switch(
        value: _isDark, 
        onChanged: _handleChange, // Toggle on switch click
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    );
  }
}