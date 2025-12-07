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

class _HomePageContentState extends State<HomePageContent> {
  final ScrollController _recommendedScrollController = ScrollController();

  @override
  void dispose() {
    _recommendedScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HomePage(
      scrollController: widget.scrollController,
      recommendedScrollController: _recommendedScrollController,
    );
  }
}