import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Import for TwitterTheme and languageNotifier
import '../auth_gate.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  // Daftar bahasa yang didukung
  final List<Map<String, String>> _supportedLanguages = [
    {'code': 'en', 'name': 'English', 'label': 'Continue'},
    {'code': 'id', 'name': 'Bahasa Indonesia', 'label': 'Lanjutkan'},
  ];

  String _selectedLanguageCode = 'en';

  @override
  void initState() {
    super.initState();
    // Set bahasa awal sesuai notifier global
    if (languageNotifier.value.languageCode == 'id') {
      _selectedLanguageCode = 'id';
    } else {
      _selectedLanguageCode = 'en';
    }
  }

  // Helper untuk mendapatkan nama bahasa yang sedang dipilih
  String get _currentLanguageName {
    final lang = _supportedLanguages.firstWhere(
      (element) => element['code'] == _selectedLanguageCode,
      orElse: () => _supportedLanguages[0],
    );
    return lang['name']!;
  }

  // Helper untuk teks tombol Continue secara dinamis
  String get _continueButtonText {
    final lang = _supportedLanguages.firstWhere(
      (element) => element['code'] == _selectedLanguageCode,
      orElse: () => _supportedLanguages[0],
    );
    return lang['label']!;
  }

  // Fungsi untuk mengganti bahasa secara real-time
  void _updateLanguage(String code) {
    setState(() {
      _selectedLanguageCode = code;
      languageNotifier.value = Locale(code); // Update global app language immediately
    });
    Navigator.of(context).pop(); // Tutup dialog
  }

  Future<void> _continue(BuildContext context) async {
    // Simpan preferensi bahasa
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', _selectedLanguageCode);
    
    // Set flag first run ke false
    await prefs.setBool('is_first_run_v1', false); 

    if (context.mounted) {
      // Navigasi ke AuthGate
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AuthGate(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  // CUSTOM POP-UP DIALOG
  void _showCustomLanguageDialog(BuildContext context) {
    final theme = Theme.of(context);
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Select Language",
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedLanguageCode == 'id' ? "Pilih Bahasa" : "Select Language",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // List Bahasa
                    ..._supportedLanguages.map((lang) {
                      final isSelected = lang['code'] == _selectedLanguageCode;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: InkWell(
                          onTap: () => _updateLanguage(lang['code']!),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? TwitterTheme.blue.withOpacity(0.1) 
                                  : theme.scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected 
                                    ? TwitterTheme.blue 
                                    : theme.dividerColor,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  lang['name']!,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? TwitterTheme.blue : theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle, 
                                    color: TwitterTheme.blue,
                                    size: 24,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon Translate
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TwitterTheme.blue.withOpacity(0.1),
                    boxShadow: [
                      BoxShadow(
                        color: TwitterTheme.blue.withOpacity(0.15),
                        blurRadius: 30,
                        spreadRadius: 10,
                      )
                    ]
                  ),
                  child: Icon(
                    Icons.translate,
                    size: 64,
                    color: TwitterTheme.blue,
                  ),
                ),
                const SizedBox(height: 48),

                // Title
                Text(
                  _selectedLanguageCode == 'id' ? "Selamat Datang" : "Welcome",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedLanguageCode == 'id' 
                      ? "Pilih bahasa untuk melanjutkan" 
                      : "Choose your language to continue",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 48),

                // CUSTOM TRIGGER BUTTON (Looks like a field)
                InkWell(
                  onTap: () => _showCustomLanguageDialog(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedLanguageCode == 'id' ? "Bahasa" : "Language",
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.hintColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentLanguageName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.scaffoldBackgroundColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: TwitterTheme.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Continue Button (Dynamic Text)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _continue(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TwitterTheme.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 10,
                      shadowColor: TwitterTheme.blue.withOpacity(0.4),
                    ),
                    child: Text(
                      _continueButtonText, // "Continue" or "Lanjutkan"
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}