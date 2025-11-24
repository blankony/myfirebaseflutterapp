// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:myfirebaseflutterapp/widgets/side_panel.dart';
import 'home_page.dart';
import 'ai_assistant_page.dart';
import 'search_page.dart';
import 'profile_tab_page.dart';
import 'settings_page.dart';
import 'account_center_page.dart';
import '../../main.dart'; 
import '../../widgets/notification_sheet.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController;
  late final PageController _pageController;
  late final PageController _homePageController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _recommendedScrollController = ScrollController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
  }

  @override
  void dispose() {
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

  Future<void> _confirmSignOut(BuildContext context) async {
    final bool shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log Out'),
        content: Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (shouldLogout) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
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
        final user = _auth.currentUser;
        return [
          StreamBuilder<DocumentSnapshot>(
            stream: user != null 
                ? _firestore.collection('users').doc(user.uid).snapshots() 
                : null,
            builder: (context, snapshot) {
              final String name = (snapshot.hasData && snapshot.data!.exists)
                  ? (snapshot.data!.data() as Map<String, dynamic>)['name'] ?? 'User'
                  : 'User';

              return PopupMenuButton<String>(
                icon: Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'Share Profile') {
                    Share.share("Hey Check Out $name , On this app Link https://github.com/blankony/myfirebaseflutterapp");
                  } else if (value == 'Account Center') {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountCenterPage()));
                  } else if (value == 'Settings') {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage()));
                  } else if (value == 'Log Out') {
                    _confirmSignOut(context);
                  }
                },
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem(
                      value: 'Share Profile',
                      child: Row(children: [Icon(Icons.share, size: 20), SizedBox(width: 8), Text('Share Profile')]),
                    ),
                    PopupMenuItem(
                      value: 'Account Center',
                      child: Row(children: [Icon(Icons.account_circle, size: 20), SizedBox(width: 8), Text('Account Center')]),
                    ),
                    PopupMenuItem(
                      value: 'Settings',
                      child: Row(children: [Icon(Icons.settings, size: 20), SizedBox(width: 8), Text('Settings')]),
                    ),
                    PopupMenuItem(
                      value: 'Log Out',
                      child: Row(children: [Icon(Icons.logout, color: Colors.red, size: 20), SizedBox(width: 8), Text('Log Out', style: TextStyle(color: Colors.red))]),
                    ),
                  ];
                },
              );
            }
          ),
        ];
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
    final _widgetOptions = <Widget>[
      Column(
        children: [
          Expanded(
            child: PageView(
              controller: _homePageController,
              onPageChanged: (index) {
                _tabController.animateTo(index);
                setState(() {});
              },
              children: [
                HomePage(
                  scrollController: _scrollController,
                  isRecommended: false,
                ),
                HomePage(
                  scrollController: _recommendedScrollController,
                  isRecommended: true,
                ),
              ],
            ),
          ),
        ],
      ),
      AiAssistantPage(),
      SearchPage(
        isSearching: _isSearching,
        onSearchPressed: () {
          setState(() {
            _isSearching = !_isSearching;
          });
        },
      ),
      ProfileTabPage(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: _selectedIndex == 3
          ? null // Hide duplicate AppBar on Profile Tab
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: GestureDetector(
                onTap: () => _scaffoldKey.currentState!.openDrawer(),
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
      // FIX: Restored NotificationListener for Swipe Right to Open Drawer
      body: NotificationListener<OverscrollNotification>(
        onNotification: (overscroll) {
          if (overscroll.metrics.axis == Axis.horizontal) {
            // Check if we are at start (pixel 0) and pulling left (negative overscroll)
            if (overscroll.metrics.pixels == 0 && overscroll.overscroll < 0) {
              _scaffoldKey.currentState?.openDrawer();
            }
          }
          return false;
        },
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          children: _widgetOptions,
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

// ... (Helper classes: _ScrollAwareAppBarBackground, _AppBarAvatar, _NotificationButton, CustomAnimatedBottomBar remain the same)
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
  Uint8List? _localImageBytes;
  String? _selectedAvatarIconName;
  final String? _currentUserId = _auth.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadLocalAvatar();
  }

  Future<void> _loadLocalAvatar() async {
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String? imagePath =
        prefs.getString('profile_picture_path_$_currentUserId');
    final String? iconName =
        prefs.getString('profile_avatar_icon_$_currentUserId');

    if (mounted) {
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          setState(() {
            _localImageBytes = bytes;
            _selectedAvatarIconName = null;
          });
        }
      } else if (iconName != null) {
        setState(() {
          _localImageBytes = null;
          _selectedAvatarIconName = iconName;
        });
      } else {
        setState(() {
          _localImageBytes = null;
          _selectedAvatarIconName = null;
        });
      }
    }
  }

  IconData _getIconDataFromString(String? iconName) {
    switch (iconName) {
      case 'face':
        return Icons.face;
      case 'rocket':
        return Icons.rocket_launch;
      case 'pet':
        return Icons.pets;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserId != null
          ? _firestore.collection('users').doc(_currentUserId).snapshots()
          : null,
      builder: (context, snapshot) {
        String initial = 'U';
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String name = data['name'] ?? 'U';
          if (name.isNotEmpty) {
            initial = name[0].toUpperCase();
          }
        }

        return CircleAvatar(
          radius: 18,
          backgroundImage:
              _localImageBytes != null ? MemoryImage(_localImageBytes!) : null,
          child: (_localImageBytes == null && _selectedAvatarIconName != null)
              ? Icon(
                  _getIconDataFromString(_selectedAvatarIconName),
                  size: 20,
                  color: TwitterTheme.blue,
                )
              : (_localImageBytes == null && _selectedAvatarIconName == null)
                  ? Text(initial)
                  : null,
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
    final user = _auth.currentUser;
    if (user == null) {
      return IconButton(
          icon: Icon(Icons.notifications_none), onPressed: onPressed);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
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