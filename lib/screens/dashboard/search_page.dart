// ignore_for_file: prefer_const_constructors
import 'dart:math';
import 'package:flutter/material.dart';

class SearchPage extends StatefulWidget {
  final bool isSearching;
  final VoidCallback onSearchPressed;

  const SearchPage({
    super.key,
    required this.isSearching,
    required this.onSearchPressed,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Calculate exactly where the AppBar ends
    final double headerHeight = MediaQuery.of(context).padding.top + kToolbarHeight;
    final double searchBarHeight = 80.0; 

    return Column(
      children: [
        // 1. SPACER: Pushes everything down below the transparent AppBar
        SizedBox(height: headerHeight),

        // 2. ANIMATED SEARCH BAR
        Align(
          alignment: Alignment.topRight,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutQuart,
            width: widget.isSearching ? screenWidth : 0,
            height: widget.isSearching ? searchBarHeight : 0,
            
            child: ClipRRect(
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20)),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                child: Container(
                  width: screenWidth, 
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Center(
                    child: TextField(
                      controller: _searchController,
                      autofocus: widget.isSearching,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                      ),
                      onChanged: (value) {
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 3. ANIMATED CONTENT SPACER
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutQuart,
          height: widget.isSearching ? 0 : 20.0, 
        ),

        // 4. CONTENT AREA
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(Duration(seconds: 1));
            },
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.6, 
                alignment: Alignment.center,
                child: _searchController.text.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // --- TODO FOR BACKEND ENGINEER ---
                          // TODO: Implement Narrow AI Recommendation System
                          // Logic:
                          // 1. PRIORITY: Display new posts from "Following" accounts first.
                          // 2. Track user interactions (specifically 'likes').
                          // 3. Extract keywords/tags from liked posts (e.g., "selamat pagi", "tech", "coffee").
                          // 4. Query the database for other posts containing these keywords.
                          // 5. Prioritize showing these "similar" posts in this 'Recommended' section.
                          // ---------------------------------
                          
                          Text(
                            'Recommended post for you', 
                            style: Theme.of(context).textTheme.bodyLarge
                          ),
                        ],
                      )
                    : Text(
                        'Search results for "${_searchController.text}"', 
                        style: Theme.of(context).textTheme.bodyLarge
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}