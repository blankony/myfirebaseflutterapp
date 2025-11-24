// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myfirebaseflutterapp/widgets/side_panel.dart';
import 'home_page.dart';
import 'ai_assistant_page.dart';
import 'search_page.dart';
import 'profile_tab_page.dart';
import '../../main.dart'; 
import '../../widgets/notification_sheet.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  int _selectedIndex = 0;
  late TabController _tabController;
  late final PageController _pageController;
  late final PageController _homePageController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _recommendedScrollController = ScrollController();
  bool _isSearching = false;

  // ### NEW: Entrance Animation Controllers ###
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Crucial for KeepAliveClientMixin
  @override
  bool get wantKeepAlive => true; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Set viewportFraction to 1.0, and keep pages in memory with physics: NeverScrollableScrollPhysics (handled by PageView itself)
    // No explicit viewportFraction needed here, but we will ensure the PageView keeps pages alive.
    _pageController = PageController();
    _homePageController = PageController();

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _homePageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        setState(() {});
      }
    });

    // ### START ENTRANCE ANIMATION ###
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutQuart),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose(); // Dispose animation
    _scrollController.dispose();
    _recommendedScrollController.dispose();
    _tabController.dispose();
    _pageController.dispose();
    _homePageController.dispose();
    super.dispose();
  }

  void _showNotificationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return NotificationSheet(scrollController: scrollController);
          },
        );
      },
    );
  }

  List<Widget> _appBarActions(BuildContext context) {
    switch (_selectedIndex) {
      case 0:
        return [
          _NotificationButton(onPressed: _showNotificationSheet),
        ];
      case 1:
        return [
          PopupMenuButton<String>(
            onSelected: (value) {},
            itemBuilder: (BuildContext context) {
              return {'New Chat', 'Chat History'}.map((String choice) {
                return PopupMenuItem<String>(
                  value: choice,
                  child: Text(choice),
                );
              }).toList();
            },
          ),
        ];
      case 2:
        return [
          IconButton(
            icon: _isSearching ? Icon(Icons.close) : Icon(Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
              });
            },
          ),
        ];
      case 3:
        return []; 
      default:
        return [];
    }
  }

  void _onItemTapped(int index) {
    if ((_selectedIndex - index).abs() > 1) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Required call for AutomaticKeepAliveClientMixin
    super.build(context);

    final _widgetOptions = <Widget>[
      // Home Page (Page 0)
      KeepAlivePage(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _homePageController,
                onPageChanged: (index) {
                  _tabController.animateTo(index);
                  setState(() {});
                },
                children: [
                  // This internal PageView should also keep its pages alive
                  KeepAlivePage(
                    child: HomePage(
                      scrollController: _scrollController,
                      isRecommended: false,
                    ),
                  ),
                  KeepAlivePage(
                    child: HomePage(
                      scrollController: _recommendedScrollController,
                      isRecommended: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // AI Assistant Page (Page 1)
      KeepAlivePage(child: AiAssistantPage()),
      // Search Page (Page 2)
      KeepAlivePage(
        child: SearchPage(
          isSearching: _isSearching,
          onSearchPressed: () {
            setState(() {
              _isSearching = !_isSearching;
            });
          },
        ),
      ),
      // Profile Tab Page (Page 3)
      KeepAlivePage(child: ProfileTabPage()),
    ];

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: _selectedIndex == 3
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: isDarkMode 
                  ? SystemUiOverlayStyle.light 
                  : SystemUiOverlayStyle.dark,
              leading: GestureDetector(
                onTap: () {
                  if (hapticNotifier.value) HapticFeedback.lightImpact();
                  _scaffoldKey.currentState!.openDrawer();
                },
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _AppBarAvatar(),
                ),
              ),
              title: Image.asset(
                'images/app_icon.png',
                height: 30,
              ),
              centerTitle: true,
              actions: _appBarActions(context),
              bottom: _selectedIndex == 0
                  ? TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(text: 'Recent Posts'),
                        Tab(text: 'Recommended'),
                      ],
                    )
                  : null,
              flexibleSpace: _selectedIndex == 0 
                ? _ScrollAwareAppBarBackground(
                    scrollController: _tabController.index == 0 
                        ? _scrollController 
                        : _recommendedScrollController
                  )
                : null,
            ),
      drawer: SidePanel(
        onProfileSelected: () {
          _onItemTapped(3);
        },
      ),
      // ### APPLY ENTRANCE ANIMATION ###
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: NotificationListener<OverscrollNotification>(
            onNotification: (overscroll) {
              if (overscroll.metrics.axis == Axis.horizontal) {
                if (overscroll.metrics.pixels == 0 && overscroll.overscroll < 0) {
                  _scaffoldKey.currentState?.openDrawer();
                }
              }
              return false;
            },
            child: PageView(
              controller: _pageController,
              // Keep all pages alive to prevent full rebuilds on screen switch
              physics: NeverScrollableScrollPhysics(), // Prevent manual swiping
              onPageChanged: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              children: _widgetOptions,
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomAnimatedBottomBar(
        selectedIndex: _selectedIndex,
        onItemSelected: _onItemTapped,
        items: <BottomNavyBarItem>[
          BottomNavyBarItem(
            icon: Icon(Icons.home),
            title: Text('Home'),
            activeColor: Colors.blue,
            inactiveColor: Colors.grey,
          ),
          BottomNavyBarItem(
            icon: Icon(Icons.assistant),
            title: Text('AI Assistant'),
            activeColor: Colors.blue,
            inactiveColor: Colors.grey,
          ),
          BottomNavyBarItem(
            icon: Icon(Icons.search),
            title: Text('Search'),
            activeColor: Colors.blue,
            inactiveColor: Colors.grey,
          ),
          BottomNavyBarItem(
            icon: Icon(Icons.person),
            title: Text('Profile'),
            activeColor: Colors.blue,
            inactiveColor: Colors.grey,
          ),
        ],
      ),
    );
  }
}

// ... (Rest of HomeDashboard helper classes remain the same) ...
class _ScrollAwareAppBarBackground extends StatefulWidget {
  final ScrollController scrollController;
  
  const _ScrollAwareAppBarBackground({required this.scrollController});

  @override
  State<_ScrollAwareAppBarBackground> createState() => _ScrollAwareAppBarBackgroundState();
}

class _ScrollAwareAppBarBackgroundState extends State<_ScrollAwareAppBarBackground> {
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _onScroll(); 
  }

  @override
  void didUpdateWidget(covariant _ScrollAwareAppBarBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
      _onScroll(); 
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    
    final bool isScrolledNow = widget.scrollController.offset > 10;
    if (isScrolledNow != _isScrolled) {
      setState(() {
        _isScrolled = isScrolledNow;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _isScrolled ? 5.0 : 0.0,
          sigmaY: _isScrolled ? 5.0 : 0.0,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: Theme.of(context)
              .scaffoldBackgroundColor
              .withOpacity(_isScrolled ? 0.7 : 0.0),
        ),
      ),
    );
  }
}
class _AppBarAvatar extends StatefulWidget {
  const _AppBarAvatar();

  @override
  State<_AppBarAvatar> createState() => _AppBarAvatarState();
}

class _AppBarAvatarState extends State<_AppBarAvatar> {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserId != null
          ? FirebaseFirestore.instance.collection('users').doc(_currentUserId).snapshots()
          : null,
      builder: (context, snapshot) {
        
        // Defaults
        int iconId = 0;
        String? colorHex;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          iconId = data['avatarIconId'] ?? 0;
          colorHex = data['avatarHex'];
        }

        // Use Universal System
        return CircleAvatar(
          radius: 18,
          backgroundColor: AvatarHelper.getColor(colorHex),
          child: Icon(
            AvatarHelper.getIcon(iconId),
            size: 20,
            color: Colors.white,
          ),
        );
      },
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _NotificationButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
          icon: Icon(Icons.notifications_none), onPressed: onPressed);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final bool hasUnread =
            snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return Stack(
          children: [
            IconButton(
              icon: Icon(
                hasUnread ? Icons.notifications : Icons.notifications_none,
              ),
              onPressed: onPressed,
            ),
            if (hasUnread)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: TwitterTheme.blue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ### NEW KeepAlive Wrapper ###
class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key, required this.child});
  final Widget child;

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
  
  @override
  bool get wantKeepAlive => true;
}


class CustomAnimatedBottomBar extends StatelessWidget {
  const CustomAnimatedBottomBar({
    Key? key,
    this.selectedIndex = 0,
    this.showElevation = true,
    this.iconSize = 24,
    this.backgroundColor,
    this.itemCornerRadius = 50,
    this.containerHeight = 56,
    this.animationDuration = const Duration(milliseconds: 150),
    this.mainAxisAlignment = MainAxisAlignment.spaceBetween,
    required this.items,
    required this.onItemSelected,
    this.curve = Curves.linear,
  })  : assert(items.length >= 2 && items.length <= 5),
        super(key: key);

  final int selectedIndex;
  final double iconSize;
  final Color? backgroundColor;
  final bool showElevation;
  final Duration animationDuration;
  final List<BottomNavyBarItem> items;
  final ValueChanged<int> onItemSelected;
  final MainAxisAlignment mainAxisAlignment;
  final double itemCornerRadius;
  final double containerHeight;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).bottomAppBarTheme.color;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          if (showElevation)
            const BoxShadow(
              color: Colors.black12,
              blurRadius: 2,
            ),
        ],
      ),
      child: SafeArea(
        child: Container(
          width: double.infinity,
          height: containerHeight,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            mainAxisAlignment: mainAxisAlignment,
            children: items.map((item) {
              var index = items.indexOf(item);
              return GestureDetector(
                onTap: () => onItemSelected(index),
                child: _ItemWidget(
                  item: item,
                  iconSize: iconSize,
                  isSelected: index == selectedIndex,
                  backgroundColor: bgColor,
                  itemCornerRadius: itemCornerRadius,
                  animationDuration: animationDuration,
                  curve: curve,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ItemWidget extends StatelessWidget {
  final double iconSize;
  final bool isSelected;
  final BottomNavyBarItem item;
  final Color? backgroundColor;
  final double itemCornerRadius;
  final Duration animationDuration;
  final Curve curve;

  const _ItemWidget({
    Key? key,
    required this.item,
    required this.isSelected,
    required this.backgroundColor,
    required this.animationDuration,
    required this.itemCornerRadius,
    required this.iconSize,
    this.curve = Curves.linear,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      selected: isSelected,
      child: AnimatedContainer(
        width: isSelected ? 130 : 50,
        height: double.maxFinite,
        duration: animationDuration,
        curve: curve,
        decoration: BoxDecoration(
          color:
              isSelected ? item.activeColor.withOpacity(0.2) : (backgroundColor ?? Colors.transparent),
          borderRadius: BorderRadius.circular(itemCornerRadius),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: NeverScrollableScrollPhysics(),
          child: Container(
            width: isSelected ? 130 : 50,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                IconTheme(
                  data: IconThemeData(
                    size: iconSize,
                    color: isSelected ? item.activeColor : item.inactiveColor,
                  ),
                  child: item.icon,
                ),
                if (isSelected)
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: item.activeColor,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        textAlign: item.textAlign,
                        child: item.title,
                      ),
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

class BottomNavyBarItem {
  BottomNavyBarItem({
    required this.icon,
    required this.title,
    this.activeColor = Colors.blue,
    this.textAlign,
    this.inactiveColor,
  });

  final Widget icon;
  final Widget title;
  final Color activeColor;
  final Color? inactiveColor;
  final TextAlign? textAlign;
}