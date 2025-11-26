// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:async'; // PENTING: Untuk StreamController
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:myfirebaseflutterapp/widgets/side_panel.dart';
import 'package:myfirebaseflutterapp/widgets/ai_history_drawer.dart'; // IMPORT DRAWER BARU
import 'home_page.dart';
import 'ai_assistant_page.dart';
import 'search_page.dart';
import 'profile_tab_page.dart';
import 'profile_page.dart'; 
import '../create_post_screen.dart'; 
import '../../main.dart'; 
import 'package:timeago/timeago.dart' as timeago; 

import '../../services/overlay_service.dart';
import '../../services/notification_prefs_service.dart';
import 'package:myfirebaseflutterapp/screens/post_detail_screen.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  int _selectedIndex = 0;
  int _subTabIndex = 0; 
  
  late TabController _tabController;
  late final PageController _pageController;
  late final PageController _homePageController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  final ScrollController _scrollController = ScrollController();
  final ScrollController _recommendedScrollController = ScrollController();
  
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
    
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController(initialPage: _selectedIndex);
    _homePageController = PageController(initialPage: _subTabIndex);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _homePageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        if (mounted) setState(() {
          _subTabIndex = _tabController.index;
        });
      }
    });

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

    final int? savedSubIndex = PageStorage.of(context).readState(context, identifier: 'home_sub_tab_index') as int?;
    if (savedSubIndex != null) {
      _subTabIndex = savedSubIndex;
      _tabController.index = _subTabIndex; 
      if (_homePageController.hasClients) {
         _homePageController.jumpToPage(_subTabIndex);
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
             message = "Someone liked your post. Tap to view.";
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
                _onItemTapped(3); 
              }
            }
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _entranceController.dispose(); 
    _scrollController.dispose();
    _recommendedScrollController.dispose();
    _tabController.dispose();
    _pageController.dispose();
    _homePageController.dispose();
    super.dispose();
  }

  void _showNotificationPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.black.withOpacity(0.4), 
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _NotificationBlurPopup();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
          alignment: Alignment(0.9, -0.95),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  void _navigateToCreatePost() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => CreatePostScreen(),
      ),
    );
  }

  // === 1. MODIFIKASI ACTIONS UNTUK TAB AI (INDEX 1) ===
  List<Widget> _appBarActions(BuildContext context) {
    switch (_selectedIndex) {
      case 0:
        return [ _NotificationButton(onPressed: _showNotificationPopup) ];
      case 1:
        // Tombol khusus untuk membuka Panel History
        return [
          IconButton(
            icon: const Icon(Icons.history), // Ikon History
            tooltip: 'Chat History',
            onPressed: () {
              // Membuka Panel Kanan (End Drawer)
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ];
      case 2:
        return [
          IconButton(
            icon: _isSearching ? Icon(Icons.close) : Icon(Icons.search),
            onPressed: () { setState(() { _isSearching = !_isSearching; }); },
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
      PageStorage.of(context).writeState(context, _selectedIndex, identifier: 'home_tab_index');
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 

    final _widgetOptions = <Widget>[
      KeepAlivePage(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _homePageController,
                onPageChanged: (index) {
                  _tabController.animateTo(index);
                  setState(() {
                    _subTabIndex = index;
                    PageStorage.of(context).writeState(context, _subTabIndex, identifier: 'home_sub_tab_index');
                  });
                },
                children: [
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

    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      extendBodyBehindAppBar: true,
      
      // === 2. TAMBAHKAN END DRAWER DI SINI ===
      // Ini adalah Side Panel yang muncul dari kanan
      endDrawer: _selectedIndex == 1 
          ? AiHistoryDrawer(
              onNewChat: () {
                 // Kirim sinyal ke AiAssistantPage untuk reset
                 aiPageEventBus.fire(AiPageEvent(type: AiEventType.newChat));
              },
              onChatSelected: (sessionId) {
                 // Kirim sinyal ke AiAssistantPage untuk load session
                 aiPageEventBus.fire(AiPageEvent(type: AiEventType.loadChat, sessionId: sessionId));
              },
            ) 
          : null,

      appBar: _selectedIndex == 3
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
              title: Image.asset('images/app_icon.png', height: 30),
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
          _onItemTapped(3);
        },
      ),
      
      floatingActionButton: (_selectedIndex == 1 || _selectedIndex == 2)
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 20.0), 
              child: FloatingActionButton(
                onPressed: _navigateToCreatePost,
                backgroundColor: TwitterTheme.blue,
                elevation: 4,
                child: const Icon(Icons.edit_outlined, color: Colors.white),
              ),
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

// === WIDGETS PENDUKUNG (TIDAK BERUBAH) ===
class _NotificationBlurPopup extends StatefulWidget {
  @override
  State<_NotificationBlurPopup> createState() => _NotificationBlurPopupState();
}

class _NotificationBlurPopupState extends State<_NotificationBlurPopup> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _markNotificationsAsRead();
  }

  Future<void> _markNotificationsAsRead() async {
    if (_currentUser == null) return;
    final notifQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false);
    
    final notifSnapshot = await notifQuery.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in notifSnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: Container(
            color: Colors.black.withOpacity(0.1), 
          ),
        ),
        
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: size.width * 0.9,
              height: size.height * 0.7, 
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor, 
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
                border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Notifications",
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1),
                  
                  Expanded(
                    child: _currentUser == null
                        ? Center(child: Text("Please log in."))
                        : StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(_currentUser!.uid)
                                .collection('notifications')
                                .orderBy('timestamp', descending: true) 
                                .limit(50) 
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return Center(child: CircularProgressIndicator());
                              }
                              if (snapshot.data!.docs.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.notifications_off_outlined, size: 60, color: Colors.grey),
                                        SizedBox(height: 16),
                                        Text("No notifications yet.", style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              return ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: snapshot.data!.docs.length,
                                separatorBuilder: (context, index) => Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                                  return _NotificationTile(notificationData: data);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notificationData;
  const _NotificationTile({required this.notificationData});

  Future<DocumentSnapshot> _getSenderData(String senderId) {
    return FirebaseFirestore.instance.collection('users').doc(senderId).get();
  }

  void _navigateToNotification(BuildContext context) {
    final String type = notificationData['type'];
    Navigator.of(context).pop(); 

    if (type == 'follow') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfilePage(userId: notificationData['senderId'], includeScaffold: true), 
      ));
    } else if (type == 'like' || type == 'repost' || type == 'comment') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: notificationData['postId']),
      ));
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return "just now";
    return timeago.format(timestamp.toDate(), locale: 'en_short');
  }

  @override
  Widget build(BuildContext context) {
    final String type = notificationData['type'];
    final String senderId = notificationData['senderId'];
    final Timestamp? timestamp = notificationData['timestamp'];
    
    IconData iconData;
    Color iconColor;

    switch (type) {
      case 'follow':
        iconData = Icons.person_add;
        iconColor = TwitterTheme.blue;
        break;
      case 'like':
        iconData = Icons.favorite;
        iconColor = Colors.pink;
        break;
      case 'repost':
        iconData = Icons.repeat;
        iconColor = Colors.green;
        break;
      case 'comment':
        iconData = Icons.chat_bubble;
        iconColor = Colors.grey; 
        break;
      default:
        iconData = Icons.notifications;
        iconColor = Colors.grey;
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _getSenderData(senderId),
      builder: (context, userSnapshot) {
        String senderName = 'Someone';
        String senderInitial = 'S';
        String? senderImageUrl; 
        
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>;
          senderName = data['name'] ?? 'Anonymous';
          senderImageUrl = data['profileImageUrl']; 
          if (senderName.isNotEmpty) senderInitial = senderName[0].toUpperCase();
        }
        
        String title = '';
        String subtitle = '';

        if(type == 'follow') {
          title = '$senderName started following you';
        } else if (type == 'like') {
          title = '$senderName liked your post';
          subtitle = notificationData['postTextSnippet'] ?? '';
        } else if (type == 'repost') {
          title = '$senderName reposted your post';
          subtitle = notificationData['postTextSnippet'] ?? '';
        } else if (type == 'comment') {
          title = '$senderName replied to your post';
          subtitle = notificationData['postTextSnippet'] ?? '';
        }
        
        Widget senderAvatar;
        if (senderImageUrl != null && senderImageUrl.isNotEmpty) {
           senderAvatar = CircleAvatar(
            backgroundImage: CachedNetworkImageProvider(senderImageUrl),
            backgroundColor: Colors.grey, 
          );
        } else {
           senderAvatar = CircleAvatar(child: Text(senderInitial));
        }

        return ListTile(
          leading: Stack(
            children: [
              senderAvatar, 
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)
                  ),
                  child: Icon(iconData, size: 12, color: Colors.white),
                ),
              )
            ],
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(
            subtitle.isNotEmpty ? '$subtitle\n${_formatTimestamp(timestamp)}' : _formatTimestamp(timestamp),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          ),
          isThreeLine: subtitle.isNotEmpty,
          onTap: () => _navigateToNotification(context),
        );
      },
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

// === EVENT BUS GLOBAL ===
// Ini digunakan agar Drawer (di Home) bisa berkomunikasi dengan AiPage
enum AiEventType { newChat, loadChat }

class AiPageEvent {
  final AiEventType type;
  final String? sessionId;
  AiPageEvent({required this.type, this.sessionId});
}

class AiPageEventBus {
  final _controller = StreamController<AiPageEvent>.broadcast();
  Stream<AiPageEvent> get stream => _controller.stream;
  void fire(AiPageEvent event) => _controller.sink.add(event);
  void dispose() => _controller.close();
}

final aiPageEventBus = AiPageEventBus();