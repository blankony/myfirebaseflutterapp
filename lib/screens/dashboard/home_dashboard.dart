// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:ui';
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago; 

import '../../widgets/side_panel.dart';
import '../../widgets/ai_history_drawer.dart'; 
import 'home_page.dart';
import 'ai_assistant_page.dart';
import 'search_page.dart';
import 'profile_tab_page.dart';
import '../create_post_screen.dart'; 
import '../community/community_list_tab.dart'; 
import '../../main.dart'; 
import '../../widgets/notification_sheet.dart'; 
import '../../services/overlay_service.dart';
import '../../services/notification_prefs_service.dart';
import '../../services/ai_event_bus.dart';

import '../../services/draft_service.dart'; 
import '../post_detail_screen.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  int _selectedIndex = 0;
  
  late final PageController _pageController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  final ScrollController _scrollController = ScrollController();
  final ScrollController _recommendedScrollController = ScrollController();
  
  late Widget _persistentHomeTab;

  bool _isSearching = false;
  bool _hasRestoredState = false; 

  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  StreamSubscription<QuerySnapshot>? _notificationSubscription;

  @override
  bool get wantKeepAlive => true; 

  @override
  void initState() {
    super.initState();
    
    _pageController = PageController(initialPage: _selectedIndex);

    _persistentHomeTab = KeepAlivePage(
      child: HomePage(
        scrollController: _scrollController,
        recommendedScrollController: _recommendedScrollController,
      ),
    );

    _scrollController.addListener(() {
      if (mounted) PageStorage.of(context).writeState(context, _scrollController.offset, identifier: 'scroll_pos_0');
    });
    _recommendedScrollController.addListener(() {
      if (mounted) PageStorage.of(context).writeState(context, _recommendedScrollController.offset, identifier: 'scroll_pos_1');
    });

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), 
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0.0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutQuart),
    );
    
    _setupNotificationListener();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreState();
    });
  }

  void _restoreState() {
    if (_hasRestoredState) return; 

    bool restoredAnyState = false;

    final int? savedIndex = PageStorage.of(context).readState(context, identifier: 'home_tab_index') as int?;
    if (savedIndex != null) {
      _selectedIndex = savedIndex;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedIndex);
      }
      restoredAnyState = true;
    }

    final double? scroll0 = PageStorage.of(context).readState(context, identifier: 'scroll_pos_0') as double?;
    final double? scroll1 = PageStorage.of(context).readState(context, identifier: 'scroll_pos_1') as double?;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll0 != null && _scrollController.hasClients) {
        _scrollController.jumpTo(scroll0);
      }
      if (scroll1 != null && _recommendedScrollController.hasClients) {
        _recommendedScrollController.jumpTo(scroll1);
      }
    });
    
    if (scroll0 != null || scroll1 != null) restoredAnyState = true;

    if (restoredAnyState) {
      _entranceController.value = 1.0; 
    } else {
      _entranceController.forward();
    }
    
    _hasRestoredState = true;
    if (mounted) setState(() {});
  }

  void _setupNotificationListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _notificationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(1) 
        .snapshots()
        .listen((snapshot) {
      
      if (!notificationPrefs.allNotificationsEnabled.value || 
          !notificationPrefs.headsUpEnabled.value) {
        return;
      }

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();

        if (data['isRead'] == false) {
          final String type = data['type'] ?? 'info';
          String message = 'New Notification';
          IconData icon = Icons.notifications;
          String? postId = data['postId'];

          if (type == 'like') {
             message = "Someone liked your post.";
             icon = Icons.favorite;
          } else if (type == 'comment') {
             message = "Someone commented on your post.";
             icon = Icons.comment;
          } else if (type == 'follow') {
             message = "You have a new follower!";
             icon = Icons.person_add;
          } else if (type == 'upload_complete') {
             message = "Media uploaded successfully.";
             icon = Icons.check_circle;
          }

          OverlayService().showTopNotification(
            context, 
            message, 
            icon,
            () {
              doc.reference.update({'isRead': true});
              if (postId != null) {
                 Navigator.push(context, _AnimatedRoute(page: PostDetailScreen(postId: postId)));
              } else if (type == 'follow') {
                _onItemTapped(4); 
              }
            }
          );
        }
      }
    });
  }

  void _showPostCreationMenu(BuildContext context) async {
    // 1. Ambil Draft Terbaru
    final DraftService draftService = DraftService();
    final List<DraftPost> drafts = await draftService.getDrafts();
    
    if (!mounted) return;

    // 2. Tampilkan Dialog dengan BackdropFilter (Blur)
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.3), // Gelap transparan
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // EFEK BLUR
          child: Dialog(
            backgroundColor: Colors.transparent, // Transparan agar blur terlihat
            insetPadding: EdgeInsets.all(20),
            // UPDATE: Menggunakan Widget Stateful baru
            child: _DraftMenuContent(
              initialDrafts: drafts,
              onNewPost: () {
                Navigator.pop(ctx);
                _navigateToCreatePost(); // Buka create post kosong
              },
              onOpenDraft: (draft) {
                Navigator.pop(ctx);
                _navigateToCreatePost(draftData: draft); // Buka create post dengan data draft
              },
            ),
          ),
        );
      },
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 600), curve: Curves.easeOutQuart);
    }
  }

  void _onLogoTapped() {
    if (_selectedIndex == 0) {
      _scrollToTop();
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _entranceController.dispose(); 
    _scrollController.dispose();
    _recommendedScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _showNotificationPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54, 
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(), 
          child: DraggableScrollableSheet(
            initialChildSize: 0.75, 
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return GestureDetector(
                onTap: () {}, 
                child: NotificationSheet(scrollController: scrollController),
              );
            },
          ),
        );
      },
    );
  }

  void _navigateToCreatePost({Map<String, dynamic>? initialData, DraftPost? draftData}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => CreatePostScreen(initialData: initialData, draftData: draftData),
      ),
    );
  }

  // --- NEW: Community Selection Logic ---
  void _showCommunityPostSelector(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text("Post to Community", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('communities')
                      .where('followers', arrayContains: user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
                    
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(child: Text("You haven't joined any communities yet."));
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final String name = data['name'] ?? 'Community';
                        final String? icon = data['imageUrl'];
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: TwitterTheme.blue.withOpacity(0.1),
                            backgroundImage: icon != null ? CachedNetworkImageProvider(icon) : null,
                            child: icon == null ? Icon(Icons.groups, color: TwitterTheme.blue) : null,
                          ),
                          title: Text(name),
                          trailing: Icon(Icons.arrow_forward_ios, size: 14),
                          onTap: () {
                            Navigator.pop(ctx); // Close Sheet
                            _navigateToCreatePost(initialData: {
                              'communityId': docs[index].id,
                              'communityName': name,
                              'communityIcon': icon,
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleFabTap() {
    // Memanggil menu blur yang baru
    _showPostCreationMenu(context);
  }

  List<Widget> _appBarActions(BuildContext context) {
    switch (_selectedIndex) {
      case 0: 
        return [ _NotificationButton(onPressed: _showNotificationPopup) ];
      case 1: 
        return []; 
      case 2: 
        return [
          IconButton(
            icon: const Icon(Icons.history), 
            tooltip: 'Chat History',
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ];
      case 3: 
        return [
          IconButton(
            icon: _isSearching ? Icon(Icons.close) : Icon(Icons.search),
            onPressed: () { setState(() { _isSearching = !_isSearching; }); },
          ),
        ];
      case 4: 
        return []; 
      default:
        return [];
    }
  }

  void _onItemTapped(int index) {
    if (index == 3) { 
      if (_selectedIndex == 3) {
        setState(() { _isSearching = !_isSearching; });
      } else {
        setState(() { _isSearching = false; });
      }
    } else {
      if (_selectedIndex == 3) {
        setState(() { _isSearching = false; });
      }
    }

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
      PageStorage.of(context).writeState(context, _selectedIndex, identifier: 'home_tab_index');
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 

    final _widgetOptions = <Widget>[
      _persistentHomeTab, 
      KeepAlivePage(child: CommunityListTab()), 
      KeepAlivePage(child: AiAssistantPage()), 
      KeepAlivePage(
        child: SearchPage(
          isSearching: _isSearching,
          onSearchPressed: () { setState(() { _isSearching = !_isSearching; }); },
        ),
      ), 
      ProfileTabPage(), 
    ];

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final navBarBgColor = isDarkMode 
        ? Color(0xFF15202B).withOpacity(0.85) 
        : Colors.white.withOpacity(0.85);      
    final inactiveIconColor = isDarkMode ? Colors.white : const Color.fromARGB(170, 0, 0, 0);
    final activeIconColor = TwitterTheme.blue;

    bool showMainFab = _selectedIndex == 0 || _selectedIndex == 1 || _selectedIndex == 4;

    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      extendBodyBehindAppBar: true,
      
      endDrawer: _selectedIndex == 2 
          ? AiHistoryDrawer(
              onNewChat: () {
                 aiPageEventBus.fire(AiPageEvent(type: AiEventType.newChat));
              },
              onChatSelected: (sessionId) {
                 aiPageEventBus.fire(AiPageEvent(type: AiEventType.loadChat, sessionId: sessionId));
              },
            ) 
          : null,

      appBar: _selectedIndex == 4
          ? null 
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
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
              title: GestureDetector(
                onTap: _onLogoTapped,
                child: Image.asset('images/app_icon.png', height: 30),
              ),
              centerTitle: true,
              actions: _appBarActions(context),
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.7),
                  ),
                ),
              ),
            ),
      drawer: SidePanel(
        onProfileSelected: () {
          _onItemTapped(4); 
        },
        onCommunitySelected: () {
          _onItemTapped(1); 
        },
      ),
      
      floatingActionButton: !showMainFab ? null : Padding(
        padding: const EdgeInsets.only(bottom: 20.0), 
        child: FloatingActionButton(
          onPressed: _handleFabTap, 
          backgroundColor: TwitterTheme.blue, 
          elevation: 4, 
          child: const Icon(Icons.edit_outlined, color: Colors.white)
        )
      ),

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
              key: PageStorageKey('home_dashboard_pageview'),
              controller: _pageController,
              physics: NeverScrollableScrollPhysics(), 
              onPageChanged: (index) {
                setState(() {
                  _selectedIndex = index;
                  PageStorage.of(context).writeState(context, _selectedIndex, identifier: 'home_tab_index');
                });
              },
              children: _widgetOptions,
            ),
          ),
        ),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            decoration: BoxDecoration(
              color: navBarBgColor,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1), width: 0.5)),
            ),
            child: CustomAnimatedBottomBar(
              selectedIndex: _selectedIndex,
              onItemSelected: _onItemTapped,
              backgroundColor: const Color.fromARGB(0, 9, 9, 9), 
              items: <BottomNavyBarItem>[
                BottomNavyBarItem(
                  icon: Icon(Icons.home),
                  title: Text('Home'),
                  activeColor: activeIconColor,
                  inactiveColor: inactiveIconColor,
                ),
                BottomNavyBarItem(
                  icon: Icon(Icons.groups), 
                  title: Text('Community'),
                  activeColor: activeIconColor,
                  inactiveColor: inactiveIconColor,
                ),
                BottomNavyBarItem(
                  icon: Icon(Icons.assistant),
                  title: Text('AI Assistant'),
                  activeColor: activeIconColor,
                  inactiveColor: inactiveIconColor,
                ),
                BottomNavyBarItem(
                  icon: Icon(Icons.search),
                  title: Text('Search'),
                  activeColor: activeIconColor,
                  inactiveColor: inactiveIconColor,
                ),
                BottomNavyBarItem(
                  icon: Icon(Icons.person),
                  title: Text('Profile'),
                  activeColor: activeIconColor,
                  inactiveColor: inactiveIconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedRoute extends PageRouteBuilder {
  final Widget page;
  _AnimatedRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0); 
            const end = Offset.zero;        
            const curve = Curves.easeOutQuart;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        );
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
        int iconId = 0;
        String? colorHex;
        String? profileImageUrl; 

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          iconId = data['avatarIconId'] ?? 0;
          colorHex = data['avatarHex'];
          profileImageUrl = data['profileImageUrl']; 
        }

        return CircleAvatar(
          radius: 18,
          backgroundColor: profileImageUrl != null ? Colors.transparent : AvatarHelper.getColor(colorHex),
          backgroundImage: profileImageUrl != null ? CachedNetworkImageProvider(profileImageUrl) : null,
          child: profileImageUrl == null ?
            Icon(
              AvatarHelper.getIcon(iconId),
              size: 20,
              color: Colors.white,
            ) : null,
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
      return IconButton(icon: Icon(Icons.notifications_none), onPressed: onPressed);
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
        final bool hasUnread = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return Stack(
          children: [
            IconButton(
              icon: Icon(hasUnread ? Icons.notifications : Icons.notifications_none),
              onPressed: onPressed,
            ),
            if (hasUnread)
              Positioned(
                top: 10, right: 10,
                child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: TwitterTheme.blue, shape: BoxShape.circle),
                ),
              ),
          ],
        );
      },
    );
  }
}

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
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor, 
        boxShadow: [
          if (showElevation)
            const BoxShadow(color: Colors.black12, blurRadius: 2),
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
                  backgroundColor: Colors.transparent,
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
          color: isSelected 
              ? item.activeColor.withOpacity(0.15) 
              : (backgroundColor ?? Colors.transparent),
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

// --- UPDATED: WIDGET KONTEN MENU DRAFTS (STATEFUL UNTUK SWIPE TO DELETE) ---
class _DraftMenuContent extends StatefulWidget {
  final List<DraftPost> initialDrafts;
  final VoidCallback onNewPost;
  final Function(DraftPost) onOpenDraft;

  const _DraftMenuContent({
    required this.initialDrafts, 
    required this.onNewPost, 
    required this.onOpenDraft
  });

  @override
  State<_DraftMenuContent> createState() => _DraftMenuContentState();
}

class _DraftMenuContentState extends State<_DraftMenuContent> {
  late List<DraftPost> _localDrafts;

  @override
  void initState() {
    super.initState();
    // Inisialisasi list lokal dari data yang dikirim (ambil max 3)
    _localDrafts = widget.initialDrafts.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Color(0xFF15202B) : Colors.white;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.9), // Sedikit transparan
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 5)]
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Create Post", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          SizedBox(height: 24),
          
          // Tombol Create New
          ElevatedButton.icon(
            onPressed: widget.onNewPost,
            icon: Icon(Icons.add, color: Colors.white),
            label: Text("Create New Post", style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: TwitterTheme.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
          
          // List Draft (Max 3)
          if (_localDrafts.isNotEmpty) ...[
            SizedBox(height: 24),
            Row(children: [
              Text("Recent Drafts", style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.bold, fontSize: 13)),
              Spacer(),
              Text("${_localDrafts.length}/3", style: TextStyle(color: theme.hintColor, fontSize: 12)),
            ]),
            SizedBox(height: 8),
            
            Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: List.generate(_localDrafts.length, (index) {
                    final draft = _localDrafts[index];
                    final bool isLast = index == _localDrafts.length - 1;
                    
                    return Column(
                      children: [
                        // --- DISMISSIBLE UNTUK HAPUS ---
                        Dismissible(
                          key: Key(draft.id), // Key unik dari draft ID
                          direction: DismissDirection.startToEnd, // Slide ke kanan
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.only(left: 20),
                            color: Colors.red,
                            child: Row(
                              children: const [
                                Icon(Icons.delete, color: Colors.white),
                                SizedBox(width: 8),
                                Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                              ],
                            ),
                          ),
                          onDismissed: (direction) async {
                            // 1. Hapus dari UI Local segera
                            setState(() {
                              _localDrafts.removeAt(index);
                            });
                            
                            // 2. Panggil Service untuk hapus permanen
                            await DraftService().deleteDraft(draft.id);
                            
                            // 3. (Opsional) Tampilkan feedback kecil jika perlu, tapi visual item hilang sudah cukup jelas
                          },
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: TwitterTheme.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Icon(draft.mediaUrls.isNotEmpty ? Icons.image : Icons.text_fields, color: TwitterTheme.blue, size: 20),
                            ),
                            title: Text(
                              draft.text.isEmpty ? "Untitled Draft" : draft.text,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(timeago.format(DateTime.fromMillisecondsSinceEpoch(draft.timestamp)), style: TextStyle(fontSize: 11)),
                            trailing: Icon(Icons.arrow_forward_ios, size: 12, color: theme.hintColor),
                            onTap: () => widget.onOpenDraft(draft),
                          ),
                        ),
                        
                        if (!isLast) Divider(height: 1, indent: 60),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ] else ...[
            SizedBox(height: 16),
            Center(child: Text("No drafts saved", style: TextStyle(color: theme.hintColor))),
          ],
          
          SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: theme.hintColor)),
          )
        ],
      ),
    );
  }
}