// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Timer dan dart:async tidak lagi diperlukan di sini
import 'screens/user_info_screen.dart'; 
import 'screens/dashboard/home_dashboard.dart'; 

// Instances
final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class DecisionGate extends StatefulWidget {
  const DecisionGate({super.key});

  @override
  State<DecisionGate> createState() => _DecisionGateState();
}

class _DecisionGateState extends State<DecisionGate> {
  // Semua state dan fungsi terkait verifikasi email (Timer, _checkEmailVerification, dll.)
  // telah dihapus dari file ini.

  @override
  Widget build(BuildContext context) {
    final User? user = _auth.currentUser;
    
    // Jika (karena alasan aneh) user null, kembali ke loading
    if (user == null) {
       return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 1. Cek Kelengkapan Profil (Nama & NIM) di Firestore
    // Blokir 'if (!_isEmailVerified)' telah dihapus.
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        // Loading cek profil
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Error ambil data
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        // Dokumen tidak ditemukan, atau 'name'/'nim' field-nya null atau kosong
        if (!snapshot.hasData || !snapshot.data!.exists) {
           // Arahkan ke UserInfoScreen untuk membuat/melengkapi data
          return const UserInfoScreen();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String? name = data['name'] as String?;
        final String? nim = data['nim'] as String?;

        if (name == null || name.isEmpty || nim == null || nim.isEmpty) {
           // Arahkan ke UserInfoScreen untuk melengkapi data
          return const UserInfoScreen();
        }

        // 2. Profil lengkap, arahkan ke dashboard utama
        // Pengguna sekarang bisa masuk meski email belum diverifikasi.
        return const HomeDashboard();
      },
    );
  }
}