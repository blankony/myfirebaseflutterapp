// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import '../../main.dart'; 

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true, // Allow blobs
      appBar: AppBar(
        title: const Text('About SAPA PNJ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.primaryColor),
      ),
      body: Stack(
        children: [
          // --- BACKGROUND BLOBS (Consistent UI) ---
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

          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 120.0, 24.0, 24.0), // Top padding for AppBar
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ]
                    ),
                    child: Image.asset('images/app_icon.png', height: 80, width: 80),
                  ),
                  
                  SizedBox(height: 24),

                  Text(
                    'SAPA PNJ',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: TwitterTheme.blue,
                    ),
                  ),
                  Text(
                    'Sarana Pengguna Aplikasi Politeknik Negeri Jakarta',
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
                    textAlign: TextAlign.center,
                  ),
                  
                  SizedBox(height: 32),
                  
                  // Explanation Card
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "About the App",
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Sapa PNJ is a social platform for the Politeknik Negeri Jakarta community. It facilitates communication between students and lecturers, allowing them to share campus news, academic updates, and daily life moments in real-time.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Our Identity",
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "The app icon features the official logo of Politeknik Negeri Jakarta, symbolizing our commitment to serving the academic ecosystem.",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 40),
                  
                  Text(
                    'Meet the Creators',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 24),
                  
                  // Creators Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCreatorProfile(
                        context,
                        'Arnold Holyridho R.',
                        'images/arnold.png',
                      ),
                      _buildCreatorProfile(
                        context,
                        'Arya Setiawan',
                        'images/arya.png',
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 40),
                  Text(
                    'Version 1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorProfile(BuildContext context, String name, String imagePath) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: TwitterTheme.blue, width: 2),
          ),
          child: CircleAvatar(
            radius: 45,
            backgroundColor: theme.scaffoldBackgroundColor,
            child: ClipOval(
              child: Image.asset(
                imagePath,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person, 
                    size: 40, 
                    color: theme.hintColor.withOpacity(0.3)
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 120,
          child: Text(
            name, 
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}