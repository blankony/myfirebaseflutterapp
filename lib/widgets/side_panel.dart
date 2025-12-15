// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
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
import '../screens/webview_screen.dart'; 
import '../screens/drafts_screen.dart'; 
import '../services/app_localizations.dart'; 

final FirebaseAuth _auth = FirebaseAuth.instance;

class SidePanel extends StatefulWidget {
  final VoidCallback onProfileSelected;
  final VoidCallback onCommunitySelected; 

  const SidePanel({
    super.key,
    required this.onProfileSelected,
    required this.onCommunitySelected, 
  });

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _signOut() async {
    var t = AppLocalizations.of(context)!;
    
    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.translate('settings_logout')), 
        content: Text(t.translate('settings_logout_confirm')), 
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.translate('general_cancel'))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t.translate('settings_logout'), style: TextStyle(color: Colors.red))),
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
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  void _openWebService(String title, String url) {
    Navigator.pop(context); 
    Navigator.of(context).push(
      _createSlideUpRoute(WebViewScreen(url: url, title: title)),
    );
  }

  void _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = themeNotifier.value == ThemeMode.dark;
    final newMode = !isDark;
    await prefs.setBool('is_dark_mode', newMode);
    themeNotifier.value = newMode ? ThemeMode.dark : ThemeMode.light;
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text("Select Language", style: theme.textTheme.titleLarge),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Text("🇺🇸", style: TextStyle(fontSize: 24)),
                title: Text("English"),
                trailing: languageNotifier.value.languageCode == 'en' 
                    ? Icon(Icons.check, color: Colors.blue) 
                    : null,
                onTap: () async {
                  await _changeLanguage('en');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Text("🇮🇩", style: TextStyle(fontSize: 24)),
                title: Text("Bahasa Indonesia"),
                trailing: languageNotifier.value.languageCode == 'id' 
                    ? Icon(Icons.check, color: Colors.blue) 
                    : null,
                onTap: () async {
                  await _changeLanguage('id');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  Future<void> _changeLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    languageNotifier.value = Locale(code);
  }

  // --- WIDGET HELPER: Modern Menu Item ---
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(icon, color: iconColor, size: 24),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), // Modern Pill Shape
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var t = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
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
            radius: 30, 
            backgroundColor: profileImageUrl != null ? Colors.transparent : (Colors.blue),
            backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
            child: profileImageUrl == null ?
              Icon(Icons.person, size: 30, color: Colors.white) 
              : null,
          );

          try {
             avatarWidget = CircleAvatar(
              radius: 30,
              backgroundColor: profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex),
              backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
              child: profileImageUrl == null ?
                Icon(AvatarHelper.getIcon(iconId), size: 30, color: Colors.white)
                : null,
            );
          } catch (e) {
            // Fallback handled
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- MODERN HEADER (Height Increased to 220 to fix Overflow) ---
              SizedBox(
                height: 220, 
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background Banner
                    if (bannerImageUrl != null && bannerImageUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: bannerImageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: theme.primaryColor.withOpacity(0.2)),
                      )
                    else
                      Container(color: theme.primaryColor.withOpacity(0.1)),

                    // Gradient
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.0),
                            Colors.black.withOpacity(0.6),
                            Colors.black.withOpacity(0.9),
                          ],
                          stops: const [0.0, 0.6, 1.0]
                        ),
                      ),
                    ),

                    // Content
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Row: Avatar & Close Button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () {
                                     Navigator.pop(context);
                                     widget.onProfileSelected();
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]
                                    ),
                                    child: avatarWidget,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close_rounded, color: Colors.white70),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                            Spacer(),
                            // User Info (Name & Handle)
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                widget.onProfileSelected();
                              },
                              child: SizedBox(
                                width: double.infinity, // Paksa ambil lebar penuh
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min, // Agar tidak makan tempat vertikal berlebih
                                  children: [
                                    Text(
                                      name, 
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                      maxLines: 1, 
                                      overflow: TextOverflow.ellipsis, // Potong jika kepanjangan
                                    ),
                                    SizedBox(height: 2), // Sedikit jarak
                                    Text(
                                      handle, 
                                      style: TextStyle(fontSize: 14, color: Colors.white70),
                                      maxLines: 1, 
                                      overflow: TextOverflow.ellipsis, // Potong email panjang jadi ...
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 12),

              // --- MENU LIST ---
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero, 
                  children: [
                    _buildMenuItem(
                      icon: Icons.account_circle_outlined,
                      title: t.translate('settings_account'),
                      onTap: () {
                        Navigator.pop(context); 
                        Navigator.of(context).push(_createSlideUpRoute(AccountCenterPage()));
                      }
                    ),
                    _buildMenuItem(
                      icon: Icons.groups_2_outlined,
                      title: t.translate('side_communities'),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onCommunitySelected();
                      }
                    ),

                    // Expandable Services
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          leading: Icon(Icons.school_outlined, color: Colors.blue), 
                          title: Text(
                            t.translate('side_services'), 
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue),
                          ),
                          childrenPadding: EdgeInsets.only(left: 12),
                          children: [
                            ListTile(
                              leading: Icon(Icons.fingerprint, color: Colors.teal, size: 20),
                              title: Text('SPIRIT ACADEMIA', style: TextStyle(fontSize: 14)),
                              onTap: () => _openWebService("SPIRIT ACADEMIA", "https://academia.pnj.ac.id/"),
                              dense: true,
                            ),
                            ListTile(
                              leading: Icon(Icons.laptop_chromebook, color: Colors.orange, size: 20),
                              title: Text('E-Learning', style: TextStyle(fontSize: 14)),
                              onTap: () => _openWebService("E-Learning PNJ", "https://elearning.pnj.ac.id/"),
                              dense: true,
                            ),
                             ListTile(
                              leading: Icon(Icons.bar_chart, color: Colors.purple, size: 20),
                              title: Text('Akademik PNJ', style: TextStyle(fontSize: 14)),
                              onTap: () => _openWebService("Akademik PNJ", "https://akademik.pnj.ac.id/"),
                              dense: true,
                            ),
                            ListTile(
                              leading: Icon(Icons.language, color: Colors.blueGrey, size: 20),
                              title: Text(t.translate('service_website'), style: TextStyle(fontSize: 14)),
                              onTap: () => _openWebService("Official Website", "https://pnj.ac.id/"),
                              dense: true,
                            ),
                          ],
                        ),
                      ),
                    ),

                    Divider(height: 24, thickness: 1, indent: 24, endIndent: 24),

                    _buildMenuItem(
                      icon: Icons.bookmark_border_rounded,
                      title: t.translate('side_saved'),
                      onTap: () {
                        Navigator.pop(context); 
                        Navigator.of(context).push(_createSlideUpRoute(SavedPostsScreen()));
                      }
                    ),
                    _buildMenuItem(
                      icon: Icons.settings_outlined,
                      title: t.translate('settings_title'),
                      onTap: () {
                        Navigator.pop(context); 
                        Navigator.of(context).push(_createSlideUpRoute(SettingsPage()));
                      }
                    ),
                  ],
                ),
              ),

              // --- BOTTOM CONTROL BAR ---
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _toggleTheme,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isDark ? Icons.light_mode : Icons.dark_mode,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _showLanguageDialog,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.translate, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 12),
                      
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _signOut,
                          icon: Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                          label: Text(
                            t.translate('settings_logout'), 
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            backgroundColor: Colors.redAccent.withOpacity(0.1),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}