// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; 
import 'screens/splash_screen.dart'; 

// Notifier global, di-set ke dark mode secara default
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// Definisikan warna tema
class TwitterTheme {
  static const Color blue = Color(0xFF1DA1F2);
  static const Color black = Color(0xFF14171A);
  static const Color darkGrey = Color(0xFF657786);
  static const Color lightGrey = Color(0xFFAAB8C2);
  static const Color extraLightGrey = Color(0xFFE1E8ED);
  static const Color white = Color(0xFFFFFFFF);

  // --- TEMA GELAP (Sudah Benar) ---
  static ThemeData darkTheme = ThemeData(
    primarySwatch: Colors.blue,
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Color(0xFF15202B), 
    cardColor: Color(0xFF192734), 
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

  // ### TEMA TERANG BARU ###
  static ThemeData lightTheme = ThemeData(
    primarySwatch: Colors.blue,
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: TwitterTheme.white, // Latar belakang putih
    cardColor: TwitterTheme.white, // Kartu putih
    primaryColor: blue,
    hintColor: darkGrey,
    dividerColor: extraLightGrey, // Garis pemisah abu-abu muda
    
    appBarTheme: AppBarTheme(
      color: TwitterTheme.white, // AppBar putih
      elevation: 0,
      iconTheme: IconThemeData(color: blue),
      // Teks AppBar hitam agar terlihat
      titleTextStyle: TextStyle(color: black, fontSize: 20, fontWeight: FontWeight.bold), 
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: extraLightGrey, // Isian abu-abu muda
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
      color: darkGrey, // Ikon abu-abu gelap
    ),

    textTheme: TextTheme(
      bodyLarge: TextStyle(color: black), // Teks hitam
      bodyMedium: TextStyle(color: black), // Teks hitam
      titleMedium: TextStyle(color: black, fontWeight: FontWeight.bold),
      titleSmall: TextStyle(color: darkGrey),
      headlineMedium: TextStyle(color: black, fontWeight: FontWeight.bold), // Teks hitam
    ),
  );
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
          title: 'Firebase Auth Demo',
          
          // ### PERBAIKAN DI SINI ###
          theme: TwitterTheme.lightTheme, // Gunakan lightTheme yang baru
          darkTheme: TwitterTheme.darkTheme, 
          
          themeMode: currentMode, 
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false, 
        );
      },
    );
  }
}