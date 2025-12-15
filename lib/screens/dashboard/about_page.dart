// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _launchRepo() async {
    final Uri url = Uri.parse('https://github.com/blankony/myfirebaseflutterapp');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('About SAPA PNJ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.primaryColor),
      ),
      body: Stack(
        children: [
          // Background Blobs
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
              padding: const EdgeInsets.fromLTRB(24.0, 120.0, 24.0, 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo with gradient background
                  Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          TwitterTheme.blue.withOpacity(0.1),
                          TwitterTheme.blue.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TwitterTheme.blue.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Image.asset('images/app_icon.png', height: 80, width: 80),
                  ),

                  SizedBox(height: 24),

                  // App Title
                  Text(
                    'SAPA PNJ',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: TwitterTheme.blue,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Sarana Pengguna Aplikasi\nPoliteknik Negeri Jakarta',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.hintColor,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: 32),

                  // About Card
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: TwitterTheme.blue.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: TwitterTheme.blue,
                              size: 24,
                            ),
                            SizedBox(width: 12),
                            Text(
                              "Tentang Aplikasi",
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: TwitterTheme.blue,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'SAPA PNJ adalah platform media sosial untuk komunitas Politeknik Negeri Jakarta. Memfasilitasi komunikasi antara mahasiswa dan dosen untuk berbagi berita kampus, update akademik, dan momen kehidupan sehari-hari.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.85),
                          ),
                        ),
                        SizedBox(height: 16),
                        Divider(color: theme.dividerColor.withOpacity(0.5)),
                        SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.school, color: TwitterTheme.blue, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Identitas Kami",
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "Logo aplikasi menampilkan logo resmi PNJ, melambangkan komitmen melayani ekosistem akademik.",
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.4,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 40),

                  // Creators Section Header
                  Text(
                    'Tim Pengembang',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: TwitterTheme.blue,
                    ),
                  ),
                  SizedBox(height: 24),

                  // Creators Cards
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildCreatorProfile(
                        context,
                        'Arnold Holyridho R.',
                        '2303421041',
                        'images/arnold.png',
                      ),
                      _buildCreatorProfile(
                        context,
                        'Arya Setiawan',
                        '2303421026',
                        'images/arya.png',
                      ),
                    ],
                  ),

                  SizedBox(height: 40),

                  // Repository Link Button
                  OutlinedButton.icon(
                    onPressed: _launchRepo,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      side: BorderSide(color: TwitterTheme.blue, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    icon: Icon(Icons.code, size: 20, color: TwitterTheme.blue),
                    label: Text(
                      "Lihat Source Code",
                      style: TextStyle(
                        color: TwitterTheme.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  SizedBox(height: 24),

                  // Version
                  Text(
                    'Version 1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorProfile(BuildContext context, String name, String nim, String imagePath) {
    final theme = Theme.of(context);

    return Container(
      width: 145,
      // Increased height slightly to 210 to give the Spacer more room to breathe
      // Fixed height is required for Spacer to work effectively in this context
      height: 210,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: TwitterTheme.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Profile Image
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: TwitterTheme.blue,
                width: 2.5,
              ),
            ),
            child: CircleAvatar(
              radius: 38,
              backgroundColor: theme.scaffoldBackgroundColor,
              child: ClipOval(
                child: Image.asset(
                  imagePath,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.person,
                      size: 38,
                      color: theme.hintColor.withOpacity(0.3),
                    );
                  },
                ),
              ),
            ),
          ),
          SizedBox(height: 12),
          
          // Name
          Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          // --- KUNCI UTAMA DI SINI ---
          // Spacer ini akan menekan widget di bawahnya (NIM) mentok ke bawah container
          Spacer(), 
          
          // NIM
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: TwitterTheme.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              nim,
              style: theme.textTheme.bodySmall?.copyWith(
                color: TwitterTheme.blue,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}