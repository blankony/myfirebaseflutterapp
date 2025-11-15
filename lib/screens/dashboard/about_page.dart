// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Application Description',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              const Text(
                'This is a Firebase Authentication and Flutter demo app for student data management.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Text(
                'Created by:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ### PERUBAHAN DI SINI ###
                  _buildCreatorProfile(
                    context,
                    'Arnold Holyridho Runtuwene',
                    'images/arnold.png', // Menggunakan path aset lokal
                  ),
                  // ### PERUBAHAN DI SINI ###
                  _buildCreatorProfile(
                    context,
                    'Arya Setiawan',
                    'images/arya.png', // Menggunakan path aset lokal
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ### PERUBAHAN DI SINI ###
  // Widget ini sekarang menerima path aset, bukan URL opsional
  Widget _buildCreatorProfile(BuildContext context, String name, String imagePath) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          // Menggunakan AssetImage untuk memuat gambar dari folder images/
          backgroundImage: AssetImage(imagePath),
          // Tambahkan fallback jika gambar gagal dimuat (opsional)
          onBackgroundImageError: (exception, stackTrace) {
            // Anda bisa log error di sini jika perlu
          },
          // Tampilkan icon jika gambar gagal dimuat
          child: Builder(builder: (context) {
            final imageProvider = AssetImage(imagePath);
            return FutureBuilder(
              future: precacheImage(imageProvider, context),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError) {
                  return Container(); // Gambar berhasil, tampilkan background
                }
                // Tampilkan inisial jika error
                return Icon(Icons.person, size: 50);
              },
            );
          }),
        ),
        const SizedBox(height: 10),
        Text(name, textAlign: TextAlign.center,),
      ],
    );
  }
}