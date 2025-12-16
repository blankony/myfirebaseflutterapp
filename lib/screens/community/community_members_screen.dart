// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../main.dart';
import '../dashboard/profile_page.dart';
import '../../services/overlay_service.dart';
import '../../services/app_localizations.dart'; // IMPORT LOCALIZATION
import 'dart:math';

class CommunityMembersScreen extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic> communityData;
  final bool isStaff; 

  const CommunityMembersScreen({
    super.key,
    required this.communityId,
    required this.communityData,
    required this.isStaff,
  });

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> with SingleTickerProviderStateMixin {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // LOCALIZATION
    var t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.translate('community_members')), // "Anggota" / "Members"
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: TwitterTheme.blue,
          unselectedLabelColor: theme.hintColor,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [
            Tab(text: t.translate('profile_followers')), // "Pengikut" / "Followers"
            Tab(text: "Admins & Staff"), // Belum ada key khusus, biarkan dulu atau gunakan 'comm_admins' jika sudah ditambahkan
          ],
        ),
      ),
      body: Stack(
        children: [
           // Blobs for vibe
           Positioned(top: 50, right: -50, child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: TwitterTheme.blue.withOpacity(isDark ? 0.05 : 0.03)))),
           
           TabBarView(
            controller: _tabController,
            children: [
              _FollowersList(
                communityId: widget.communityId,
                followersList: widget.communityData['followers'] ?? [],
              ),
              _AdminsList(
                communityId: widget.communityId,
                communityData: widget.communityData,
                isStaff: widget.isStaff,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FollowersList extends StatelessWidget {
  final String communityId;
  final List followersList;

  const _FollowersList({required this.communityId, required this.followersList});

  @override
  Widget build(BuildContext context) {
    var t = AppLocalizations.of(context)!;
    
    // "Tidak ada hasil untuk" + " " + "Pengikut" = "Tidak ada hasil untuk Pengikut" / "No followers yet"
    if (followersList.isEmpty) return Center(child: Text("${t.translate('search_no_results')} ${t.translate('profile_followers')}", style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      itemCount: followersList.length,
      itemBuilder: (context, index) {
        final userId = followersList[index];
        // Custom Manual Animation
        return _DelayedSlideFade(
          delay: index * 50, // 50ms stagger
          child: _UserTile(userId: userId),
        );
      },
    );
  }
}

class _AdminsList extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic> communityData;
  final bool isStaff;

  const _AdminsList({required this.communityId, required this.communityData, required this.isStaff});

  @override
  State<_AdminsList> createState() => _AdminsListState();
}

class _AdminsListState extends State<_AdminsList> {
  // --- ANIMATED DIALOG (MATCHING SETTINGS SCREEN) ---
  void _showEditRoleDialog(BuildContext context, String userId, String currentTitle, Color currentColor) {
    final TextEditingController titleController = TextEditingController(text: currentTitle);
    Color selectedColor = currentColor;
    var t = AppLocalizations.of(context)!;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: t.translate('general_close'),
      transitionDuration: Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Align(
              alignment: Alignment.center,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: EdgeInsets.all(20),
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0,4))],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Customize Role", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 20),
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(labelText: "Role Title", filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                        ),
                        SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          children: [
                            ...AvatarHelper.presetColors.take(5).map((c) => GestureDetector(
                              onTap: () => setState(() => selectedColor = c),
                              child: Container(width: 32, height: 32, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: selectedColor == c ? Border.all(width: 3, color: Colors.black) : null)),
                            )),
                            IconButton(
                              icon: Icon(Icons.colorize),
                              onPressed: () {
                                showDialog(context: context, builder: (c) => AlertDialog(content: SingleChildScrollView(child: ColorPicker(pickerColor: selectedColor, onColorChanged: (c) => selectedColor = c)), actions: [ElevatedButton(onPressed: () { setState((){}); Navigator.of(c).pop(); }, child: Text("Select"))]));
                              },
                            )
                          ],
                        ),
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text(t.translate('general_cancel'))),
                            ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _updateRole(userId, titleController.text, selectedColor);
                              },
                              child: Text(t.translate('general_save')),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) => ScaleTransition(scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack), child: child),
    );
  }

  Future<void> _updateRole(String userId, String title, Color color) async {
    // Localization
    // Note: since this is async, check mounted or context
    if (!mounted) return;
    var t = AppLocalizations.of(context)!;
    
    try {
      final hex = '0x${color.value.toRadixString(16).toUpperCase()}';
      await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).set({
        'adminRoles': {userId: {'title': title, 'color': hex}}
      }, SetOptions(merge: true));
      if(mounted) OverlayService().showTopNotification(context, t.translate('general_success'), Icons.check, (){});
    } catch(e) {
      if(mounted) OverlayService().showTopNotification(context, t.translate('post_failed'), Icons.error, (){}, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>;
        
        final String ownerId = data['ownerId'];
        final List admins = data['admins'] ?? [];
        final Map<String, dynamic> roles = data['adminRoles'] ?? {};

        final List<String> allStaff = [ownerId, ...admins.map((e)=>e.toString())];

        return ListView.separated(
          padding: EdgeInsets.all(16),
          itemCount: allStaff.length,
          separatorBuilder: (_,__) => Divider(height: 1),
          itemBuilder: (context, index) {
            final userId = allStaff[index];
            final bool isOwner = userId == ownerId;
            final roleData = roles[userId] ?? {};
            final String roleTitle = roleData['title'] ?? (isOwner ? 'Owner' : 'Admin');
            final Color roleColor = AvatarHelper.getColor(roleData['color']);

            return _DelayedSlideFade(
              delay: index * 50,
              child: _UserTile(
                userId: userId,
                roleBadge: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: roleColor, borderRadius: BorderRadius.circular(8)),
                  child: Text(roleTitle, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                onEdit: (widget.isStaff) ? () => _showEditRoleDialog(context, userId, roleTitle, roleColor) : null,
              ),
            );
          },
        );
      }
    );
  }
}

// --- HELPER FOR ANIMATION ---
class _DelayedSlideFade extends StatefulWidget {
  final Widget child;
  final int delay;

  const _DelayedSlideFade({required this.child, required this.delay});

  @override
  State<_DelayedSlideFade> createState() => _DelayedSlideFadeState();
}

class _DelayedSlideFadeState extends State<_DelayedSlideFade> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: widget.child,
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String userId;
  final Widget? roleBadge;
  final VoidCallback? onEdit;

  const _UserTile({required this.userId, this.roleBadge, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox(height: 60);
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final name = data['name'] ?? 'User';
        final url = data['profileImageUrl'];
        final iconId = data['avatarIconId'] ?? 0;
        final colorHex = data['avatarHex'];

        return ListTile(
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          leading: CircleAvatar(
            backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
            backgroundColor: AvatarHelper.getColor(colorHex),
            child: url == null ? Icon(AvatarHelper.getIcon(iconId), color: Colors.white) : null,
          ),
          title: Row(
            children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
              if (roleBadge != null) ...[SizedBox(width: 8), roleBadge!],
            ],
          ),
          subtitle: Text("@${(data['email'] ?? '').split('@')[0]}"),
          trailing: onEdit != null ? IconButton(icon: Icon(Icons.edit, size: 18), onPressed: onEdit) : null,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(userId: userId, includeScaffold: true))),
        );
      },
    );
  }
}