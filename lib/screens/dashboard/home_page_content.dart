// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'home_page.dart';

class HomePageContent extends StatefulWidget {
  final ScrollController scrollController;

  const HomePageContent({
    super.key,
    required this.scrollController,
  });

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Recent Posts'),
            Tab(text: 'Recommended'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              HomePage(
                scrollController: widget.scrollController,
              ),
              Center(child: Text("Recommended Posts")), // Placeholder
            ],
          ),
        ),
      ],
    );
  }
}
