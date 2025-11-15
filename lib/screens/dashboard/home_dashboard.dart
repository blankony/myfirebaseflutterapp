// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'home_page.dart'; 
import 'profile_page.dart'; 
import 'settings_page.dart'; 

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _selectedIndex = 0;

  // ### PERUBAHAN 1: Buat _widgetOptions menjadi 'late final' ###
  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    // ### PERUBAHAN 2: Inisialisasi widget di initState ###
    // Ini agar kita bisa memberikan fungsi '_onItemTapped'
    _widgetOptions = [
      HomePage(onProfileTap: () => _onItemTapped(1)), // Berikan callback (1 = Profile)
      ProfilePage(), 
      SettingsPage(), 
    ];
  }
  // ### AKHIR PERUBAHAN ###

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack( 
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home), 
            label: 'Home', 
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings), 
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }
}