// ignore_for_file: prefer_const_constructors
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'login_page.dart';
import 'register_page.dart';
import '../main.dart'; 
import '../services/app_localizations.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

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

  // Method to toggle language
  void _toggleLanguage() async {
    final currentCode = languageNotifier.value.languageCode;
    final newCode = currentCode == 'en' ? 'id' : 'en';
    
    // Update notifier
    languageNotifier.value = Locale(newCode);

    // Save preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', newCode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    var t = AppLocalizations.of(context)!;

    return Scaffold(
      body: Stack(
        children: [
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

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  // --- HEADER ROW (LOGO + LANGUAGE TOGGLE) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Image.asset('images/app_icon.png', height: 40),
                      
                      // LANGUAGE SWITCHER ICON
                      ValueListenableBuilder<Locale>(
                        valueListenable: languageNotifier,
                        builder: (context, locale, child) {
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _toggleLanguage,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: TwitterTheme.blue.withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(12),
                                  color: theme.cardColor.withOpacity(0.5),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.translate, // CHANGED TO TRANSLATE ICON
                                      color: TwitterTheme.blue,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      locale.languageCode.toUpperCase(),
                                      style: TextStyle(
                                        color: TwitterTheme.blue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                      ),
                    ],
                  ),

                  Spacer(flex: 2), 

                  Text(
                    "SAPA", 
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 72, 
                      fontWeight: FontWeight.w900,
                      color: TwitterTheme.blue,
                      letterSpacing: -2.0,
                      height: 0.9,
                    ),
                  ),
                  Text(
                    "PNJ", 
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 72, 
                      fontWeight: FontWeight.w900,
                      color: theme.textTheme.bodyLarge?.color,
                      letterSpacing: -2.0,
                      height: 0.9,
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  Container(
                    padding: EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: TwitterTheme.blue, width: 4))
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Text(
                        t.translate('slogan'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  
                  Spacer(flex: 3), 

                  Text(
                    t.translate('welcome_join_message'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(_createSlideUpRoute(RegisterPage()));
                      },
                      child: Text(t.translate('welcome_create_account')), 
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TwitterTheme.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 18),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16), 
                        ),
                        textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  SizedBox(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
                        children: [
                          TextSpan(text: "${t.translate('auth_have_account')} "), 
                          TextSpan(
                            text: t.translate('auth_login'), 
                            style: TextStyle(
                              color: TwitterTheme.blue,
                              fontWeight: FontWeight.bold,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.of(context).push(_createSlideUpRoute(LoginPage()));
                              },
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
    );
  }
}