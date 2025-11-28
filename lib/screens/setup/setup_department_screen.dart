// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../../data/pnj_data.dart';
import 'setup_verification_screen.dart';
import '../../services/overlay_service.dart'; // REQUIRED

class SetupDepartmentScreen extends StatefulWidget {
  const SetupDepartmentScreen({super.key});

  @override
  State<SetupDepartmentScreen> createState() => _SetupDepartmentScreenState();
}

class _SetupDepartmentScreenState extends State<SetupDepartmentScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  String? _selectedDepartment;
  Map<String, String>? _selectedProdi; 
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveAndNext() async {
    if (_selectedDepartment == null || _selectedProdi == null) {
      OverlayService().showTopNotification(
        context, 
        "Please select your department and study program.", 
        Icons.warning_amber_rounded, 
        (){},
        color: Colors.orange
      );
      return;
    }

    setState(() { _isLoading = true; });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'department': _selectedDepartment,
        'studyProgram': _selectedProdi!['name'],
        'departmentCode': _selectedProdi!['code'], 
      });

      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => SetupVerificationScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        OverlayService().showTopNotification(
          context, 
          "Error: $e", 
          Icons.error, 
          (){},
          color: Colors.red
        );
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset('images/app_icon.png', height: 40),
                SizedBox(height: 32),
                Text(
                  "Where do you study?",
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: TwitterTheme.blue,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Select your department and study program to connect with peers.",
                  style: theme.textTheme.bodyLarge,
                ),
                SizedBox(height: 32),

                // Department Dropdown
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: "Department (Jurusan)",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.cardColor,
                  ),
                  value: _selectedDepartment,
                  items: PnjData.departments.keys.map((String dept) {
                    return DropdownMenuItem(value: dept, child: Text(dept));
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedDepartment = val;
                      _selectedProdi = null; 
                    });
                  },
                ),
                SizedBox(height: 20),

                // Study Program Dropdown (Dependent)
                DropdownButtonFormField<Map<String, String>>(
                  decoration: InputDecoration(
                    labelText: "Study Program (Prodi)",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: theme.cardColor,
                  ),
                  value: _selectedProdi,
                  items: _selectedDepartment == null 
                    ? [] 
                    : PnjData.departments[_selectedDepartment]!.map((Map<String, String> prodi) {
                        return DropdownMenuItem<Map<String, String>>(
                          value: prodi,
                          child: Text(prodi['name']!, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                  onChanged: _selectedDepartment == null ? null : (val) {
                    setState(() {
                      _selectedProdi = val;
                    });
                  },
                  isExpanded: true,
                ),

                Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveAndNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TwitterTheme.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isLoading 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text("Next"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}