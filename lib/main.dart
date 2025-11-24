// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; 
import 'screens/splash_screen.dart'; 

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<bool> hapticNotifier = ValueNotifier(true);

class TwitterTheme {
  static const Color blue = Color(0xFF1DA1F2);
  static const Color black = Color(0xFF14171A);
  static const Color darkGrey = Color(0xFF657786);
  static const Color lightGrey = Color(0xFFAAB8C2);
  static const Color extraLightGrey = Color(0xFFE1E8ED);
  static const Color white = Color(0xFFFFFFFF);

  static ThemeData darkTheme = ThemeData(
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: blue,
      onPrimary: white,
      secondary: blue,
      onSecondary: white,
      error: Colors.redAccent,
      onError: white,
      background: Color(0xFF15202B),
      onBackground: white,
      surface: Color(0xFF192734),
      onSurface: white,
    ),
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Color(0xFF15202B), 
    cardColor: Color(0xFF15202B), 
    primaryColor: blue,
    hintColor: darkGrey,
    dividerColor: Color(0xFF38444D), 
    
    appBarTheme: AppBarTheme(
      color: Color(0xFF15202B), 
      elevation: 0,
      iconTheme: IconThemeData(color: blue), 
      titleTextStyle: TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.bold),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF192734), 
      hintStyle: TextStyle(color: darkGrey),
      labelStyle: TextStyle(color: darkGrey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none, 
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: blue, width: 2), 
      ),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF15202B),
      selectedItemColor: blue,
      unselectedItemColor: darkGrey,
      showUnselectedLabels: false,
      showSelectedLabels: false,
      type: BottomNavigationBarType.fixed,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: blue,
      foregroundColor: white,
    ),

    iconTheme: IconThemeData(
      color: lightGrey,
    ),

    textTheme: TextTheme(
      bodyLarge: TextStyle(color: white),
      bodyMedium: TextStyle(color: white),
      titleMedium: TextStyle(color: white, fontWeight: FontWeight.bold),
      titleSmall: TextStyle(color: darkGrey),
      headlineMedium: TextStyle(color: white, fontWeight: FontWeight.bold),
    ),
  );

  static ThemeData lightTheme = ThemeData(
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: blue,
      onPrimary: white,
      secondary: blue,
      onSecondary: white,
      error: Colors.redAccent,
      onError: white,
      background: white,
      onBackground: black,
      surface: white,
      onSurface: black,
    ),
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: TwitterTheme.white, 
    cardColor: TwitterTheme.white, 
    primaryColor: blue,
    hintColor: darkGrey,
    dividerColor: extraLightGrey, 
    
    appBarTheme: AppBarTheme(
      color: TwitterTheme.white, 
      elevation: 0,
      iconTheme: IconThemeData(color: blue),
      titleTextStyle: TextStyle(color: black, fontSize: 20, fontWeight: FontWeight.bold), 
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: extraLightGrey, 
      hintStyle: TextStyle(color: darkGrey),
      labelStyle: TextStyle(color: darkGrey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: blue, width: 2),
      ),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: TwitterTheme.white,
      selectedItemColor: blue,
      unselectedItemColor: darkGrey,
      showUnselectedLabels: false,
      showSelectedLabels: false,
      type: BottomNavigationBarType.fixed,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: blue,
      foregroundColor: white,
    ),

    iconTheme: IconThemeData(
      color: darkGrey, 
    ),

    textTheme: TextTheme(
      bodyLarge: TextStyle(color: black), 
      bodyMedium: TextStyle(color: black), 
      titleMedium: TextStyle(color: black, fontWeight: FontWeight.bold),
      titleSmall: TextStyle(color: darkGrey),
      headlineMedium: TextStyle(color: black, fontWeight: FontWeight.bold), 
    ),
  );
}

// ### UPDATED AVATAR HELPER ###
class AvatarHelper {
  // Returns one of 10 icons based on ID (0-9)
  static IconData getIcon(int id) {
    switch (id) {
      case 1: return Icons.face;
      case 2: return Icons.rocket_launch;
      case 3: return Icons.pets;
      case 4: return Icons.star;
      case 5: return Icons.bolt;
      case 6: return Icons.music_note;
      case 7: return Icons.local_cafe;
      case 8: return Icons.menu_book;
      case 9: return Icons.computer;
      default: return Icons.person; // 0 is Default
    }
  }

  static Color getColor(String? hex) {
    if (hex == null || hex.isEmpty) return TwitterTheme.blue;
    try {
      return Color(int.parse(hex));
    } catch (e) {
      return TwitterTheme.blue;
    }
  }

  // Presets for the picker - ensuring uniqueness
  static const List<Color> presetColors = [
    Color(0xFF1DA1F2), // Blue
    Colors.redAccent,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pinkAccent,
    Color(0xFF78909C), // Unique: Light Blue Grey
    Color(0xFF8B4513), // Brown
    Color(0xFF607D8B), // Dark Blue Grey
  ];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Sapa PNJ', 
          theme: TwitterTheme.lightTheme, 
          darkTheme: TwitterTheme.darkTheme, 
          themeMode: currentMode, 
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false, 
        );
      },
    );
  }
}