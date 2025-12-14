// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import '../../main.dart'; 
import 'about_page.dart'; 
import '../edit_profile_screen.dart';
import 'account_center_page.dart'; 
import '../blocked_users_page.dart'; 
import '../../services/notification_prefs_service.dart'; 
import '../../services/overlay_service.dart';
import '../../services/app_localizations.dart'; // PASTIKAN IMPORT INI ADA

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  
  Route _createSlideRightRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); 
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

  void _goToAboutPage(BuildContext context) {
    Navigator.of(context).push(_createSlideRightRoute(AboutPage()));
  }
  
  void _goToAccountCenter(BuildContext context) {
    Navigator.of(context).push(_createSlideRightRoute(AccountCenterPage()));
  }

  void _goToBlockedUsers(BuildContext context) {
    Navigator.of(context).push(_createSlideRightRoute(BlockedUsersPage()));
  }

  // --- LOGIKA GANTI BAHASA ---
  void _changeLanguage(BuildContext context, String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    
    languageNotifier.value = Locale(code); 
    
    Navigator.pop(context); 
  }

  void _showLanguageDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              SizedBox(height: 16),
              ListTile(
                leading: Text("🇺🇸", style: TextStyle(fontSize: 24)),
                title: Text("English"),
                trailing: languageNotifier.value.languageCode == 'en' ? Icon(Icons.check, color: TwitterTheme.blue) : null,
                onTap: () => _changeLanguage(context, 'en'),
              ),
              ListTile(
                leading: Text("🇮🇩", style: TextStyle(fontSize: 24)),
                title: Text("Bahasa Indonesia"),
                trailing: languageNotifier.value.languageCode == 'id' ? Icon(Icons.check, color: TwitterTheme.blue) : null,
                onTap: () => _changeLanguage(context, 'id'),
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      }
    );
  }

  Future<void> _signOut(BuildContext context) async {
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

    final didConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.translate('settings_logout')), // "Log Out"
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

  @override
  Widget build(BuildContext context) {
    // LOCALIZATION INSTANCE
    var t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.translate('settings_title')), // "Settings" / "Pengaturan"
      ),
      body: ListView(
        children: [
          _buildSettingsTile(
            context: context,
            icon: Icons.account_circle_outlined,
            title: t.translate('settings_account'), // "Account Center"
            subtitle: t.translate('settings_account_desc'), 
            onTap: () => _goToAccountCenter(context),
          ),
          
          _buildSettingsTile(
            context: context,
            icon: Icons.block,
            title: t.translate('settings_blocked'), // "Blocked Accounts"
            onTap: () => _goToBlockedUsers(context),
          ),
          
          _buildSettingsTile(
            context: context,
            icon: Icons.info_outline,
            title: t.translate('settings_about'), // "About Us"
            onTap: () => _goToAboutPage(context),
          ),
          
          _OptimizedThemeTile(),

          // --- LANGUAGE TILE ---
          _buildSettingsTile(
            context: context,
            icon: Icons.language,
            title: t.translate('settings_language'), // "Change Language"
            subtitle: languageNotifier.value.languageCode == 'en' ? 'English' : 'Bahasa Indonesia',
            onTap: () => _showLanguageDialog(context),
          ),

          ValueListenableBuilder<bool>(
            valueListenable: hapticNotifier,
            builder: (context, isHapticOn, child) {
              return SwitchListTile(
                secondary: Icon(Icons.vibration, color: Theme.of(context).primaryColor),
                title: Text(t.translate('settings_haptic')), // "Haptic Feedback"
                value: isHapticOn,
                onChanged: (value) {
                  hapticNotifier.value = value;
                },
              );
            },
          ),
          
          Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              t.translate('settings_header_notif'), // "Notifications"
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: TwitterTheme.blue, fontWeight: FontWeight.bold
              ),
            ),
          ),
          
          ValueListenableBuilder<bool>(
            valueListenable: notificationPrefs.allNotificationsEnabled,
            builder: (context, isEnabled, child) {
              return SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined, color: Theme.of(context).primaryColor),
                title: Text(t.translate('settings_notif_allow')), // "Allow Notifications"
                subtitle: Text(t.translate('settings_notif_allow_desc')),
                value: isEnabled,
                onChanged: (value) {
                  notificationPrefs.setAllNotifications(value);
                },
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: notificationPrefs.allNotificationsEnabled,
            builder: (context, allEnabled, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: notificationPrefs.headsUpEnabled,
                builder: (context, headsUpEnabled, child) {
                  return SwitchListTile(
                    onChanged: allEnabled ? (value) {
                       notificationPrefs.setHeadsUp(value);
                    } : null,
                    secondary: Icon(Icons.view_day_outlined, color: allEnabled ? Theme.of(context).primaryColor : Theme.of(context).disabledColor),
                    title: Text(t.translate('settings_notif_heads')), // "Heads-up Popups"
                    subtitle: Text(t.translate('settings_notif_heads_desc')),
                    value: allEnabled && headsUpEnabled,
                  );
                },
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.cleaning_services_outlined, color: Colors.red),
            title: Text(t.translate('settings_notif_clear'), style: TextStyle(color: Colors.red)), // "Clear Notification History"
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(t.translate('settings_notif_clear_confirm')),
                  content: Text(t.translate('settings_notif_clear_desc')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.translate('general_cancel'))),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.translate('general_delete'), style: TextStyle(color: Colors.red))),
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
                     OverlayService().showTopNotification(context, t.translate('settings_notif_cleared'), Icons.check_circle, (){});
                  }
                }
              }
            },
          ),
          Divider(),

          _buildSettingsTile(
            context: context,
            icon: Icons.logout,
            title: t.translate('settings_logout'), // "Log Out"
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
    var t = AppLocalizations.of(context)!;
    final subtitleText = _isDark 
        ? t.translate('settings_theme_light') // "Switch to Light"
        : t.translate('settings_theme_dark'); // "Switch to Dark"
    
    return ListTile(
      leading: Icon(
        _isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        color: Theme.of(context).primaryColor
      ),
      title: Text(t.translate('settings_theme')), // "Theme"
      subtitle: Text(subtitleText),
      trailing: Switch(
        value: _isDark,
        onChanged: _handleChange,
      ),
    );
  }
}