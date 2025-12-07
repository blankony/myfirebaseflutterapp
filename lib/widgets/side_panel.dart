// ignore_for_file: prefer_const_constructors
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import '../main.dart';
import '../screens/dashboard/account_center_page.dart';
import '../screens/dashboard/settings_page.dart';
import '../screens/saved_posts_screen.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;

class SidePanel extends StatefulWidget {
  final VoidCallback onProfileSelected;
  final VoidCallback onCommunitySelected; // Callback Baru

  const SidePanel({
    super.key,
    required this.onProfileSelected,
    required this.onCommunitySelected, // Wajib diisi
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
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Route _createSlideUpRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); 
        const end = Offset.zero;      
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

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: StreamBuilder<DocumentSnapshot>(
        stream: _currentUserId != null
            ? FirebaseFirestore.instance.collection('users').doc(_currentUserId).snapshots()
            : null,
        builder: (context, snapshot) {
          String name = "User";
          String handle = "@user";
          
          int iconId = 0;
          String? colorHex;
          String? profileImageUrl; 
          String? bannerImageUrl; 

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            name = data['name'] ?? "User";
            final email = data['email'] ?? "";
            handle = email.isNotEmpty ? "@${email.split('@')[0]}" : "@user";
            
            iconId = data['avatarIconId'] ?? 0;
            colorHex = data['avatarHex'];
            profileImageUrl = data['profileImageUrl'];
            bannerImageUrl = data['bannerImageUrl']; 
          }

          Widget avatarWidget = CircleAvatar(
            radius: 28, 
            backgroundColor: profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex),
            backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
            child: profileImageUrl == null ?
              Icon(AvatarHelper.getIcon(iconId), size: 28, color: Colors.white)
              : null,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 220, 
                child: Stack(
                  fit: StackFit.expand,
                  children: [
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
                                  icon: Icon(Icons.close, color: Colors.white), 
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                            Spacer(),
                            
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
                                      border: Border.all(color: Colors.white, width: 2), 
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
                                            color: Colors.white 
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        Text(
                                          handle, 
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: Colors.white70 
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
                ListTile(
                  leading: Icon(Icons.account_circle_outlined), 
                  title: Text('Account Center'), 
                  onTap: () {
                    Navigator.pop(context); 
                    Navigator.of(context).push(_createSlideUpRoute(AccountCenterPage()));
                  }
                ),
                ListTile(
                  leading: Icon(Icons.groups_2_outlined), 
                  title: Text('Community'), 
                  onTap: () {
                    Navigator.pop(context);
                    widget.onCommunitySelected();
                  }
                ),
                ListTile(
                  leading: Icon(Icons.bookmark_border), 
                  title: Text('Saved'), 
                  onTap: () {
                    Navigator.pop(context); 
                    Navigator.of(context).push(_createSlideUpRoute(SavedPostsScreen()));
                  }
                ),
                ListTile(
                  leading: Icon(Icons.settings_outlined), 
                  title: Text('More Settings'), 
                  onTap: () {
                    Navigator.pop(context); 
                    Navigator.of(context).push(_createSlideUpRoute(SettingsPage()));
                  }
                ),
              ])),
              
              Divider(height: 1),
              Padding(padding: EdgeInsets.all(8), child: Column(children: [
                 _ThemeSwitchTile(),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', value);

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
      onTap: () => _handleChange(!_isDark), 
      leading: Icon(Icons.color_lens_outlined, color: theme.primaryColor), 
      title: Text('Theme'), 
      subtitle: Text(subtitleText), 
      trailing: Switch(
        value: _isDark, 
        onChanged: _handleChange, 
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    );
  }
}