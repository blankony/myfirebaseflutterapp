// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../main.dart';
import '../dashboard/profile_page.dart';
import '../../services/overlay_service.dart';
import 'dart:math';

class CommunityMembersScreen extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic> communityData;
  final bool isStaff; // If true, can edit roles

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
    return Scaffold(
      appBar: AppBar(
        title: Text("Members"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: TwitterTheme.blue,
          unselectedLabelColor: Colors.grey,
          tabs: const [Tab(text: "Followers"), Tab(text: "Admins")],
        ),
      ),
      body: TabBarView(
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
    );
  }
}

class _FollowersList extends StatelessWidget {
  final String communityId;
  final List followersList;

  const _FollowersList({required this.communityId, required this.followersList});

  @override
  Widget build(BuildContext context) {
    if (followersList.isEmpty) return Center(child: Text("No followers yet."));

    return ListView.builder(
      itemCount: followersList.length,
      itemBuilder: (context, index) {
        final userId = followersList[index];
        return _UserTile(userId: userId);
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
  void _showEditRoleDialog(BuildContext context, String userId, String currentTitle, Color currentColor) {
    final TextEditingController titleController = TextEditingController(text: currentTitle);
    Color selectedColor = currentColor;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Edit Role Appearance"),
              // WRAPPED IN SINGLECHILDSCROLLVIEW TO FIX OVERFLOW
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(labelText: "Role Title (e.g. Ketua BEM)"),
                    ),
                    SizedBox(height: 16),
                    Text("Role Color"),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ...AvatarHelper.presetColors.take(5).map((c) => GestureDetector(
                          onTap: () => setState(() => selectedColor = c),
                          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: selectedColor == c ? Border.all(width: 3, color: Colors.black) : null)),
                        )),
                        IconButton(
                          icon: Icon(Icons.shuffle),
                          onPressed: () => setState(() => selectedColor = Color((Random().nextDouble() * 0xFFFFFF).toInt()).withOpacity(1.0)),
                        ),
                        IconButton(
                          icon: Icon(Icons.colorize),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Pick a color!'),
                                content: SingleChildScrollView(
                                  child: ColorPicker(
                                    pickerColor: selectedColor,
                                    onColorChanged: (c) => selectedColor = c,
                                  ),
                                ),
                                actions: <Widget>[
                                  ElevatedButton(onPressed: () { setState((){}); Navigator.of(c).pop(); }, child: const Text('Got it')),
                                ],
                              ),
                            );
                          },
                        )
                      ],
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: selectedColor, borderRadius: BorderRadius.circular(4)),
                      child: Text(titleController.text.isEmpty ? "Admin" : titleController.text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _updateRole(userId, titleController.text, selectedColor);
                  },
                  child: Text("Save"),
                )
              ],
            );
          },
        );
      }
    );
  }

  Future<void> _updateRole(String userId, String title, Color color) async {
    try {
      final hex = '0x${color.value.toRadixString(16).toUpperCase()}';
      await FirebaseFirestore.instance.collection('communities').doc(widget.communityId).set({
        'adminRoles': {
          userId: {
            'title': title,
            'color': hex
          }
        }
      }, SetOptions(merge: true));
      if(mounted) OverlayService().showTopNotification(context, "Role Updated", Icons.check, (){});
    } catch(e) {
      if(mounted) OverlayService().showTopNotification(context, "Failed to update role", Icons.error, (){}, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-fetch data to get roles updates
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>;
        
        final String ownerId = data['ownerId'];
        final List admins = data['admins'] ?? [];
        final Map<String, dynamic> roles = data['adminRoles'] ?? {};

        final List<String> allStaff = [ownerId, ...admins.map((e)=>e.toString())];

        return ListView.builder(
          itemCount: allStaff.length,
          itemBuilder: (context, index) {
            final userId = allStaff[index];
            final bool isOwner = userId == ownerId;
            final roleData = roles[userId] ?? {};
            final String roleTitle = roleData['title'] ?? (isOwner ? 'Owner' : 'Admin');
            final Color roleColor = AvatarHelper.getColor(roleData['color']);

            return _UserTile(
              userId: userId,
              roleBadge: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: roleColor, borderRadius: BorderRadius.circular(8)),
                child: Text(roleTitle, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              onEdit: (widget.isStaff) 
                ? () => _showEditRoleDialog(context, userId, roleTitle, roleColor) 
                : null,
            );
          },
        );
      }
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
          leading: CircleAvatar(
            backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
            backgroundColor: AvatarHelper.getColor(colorHex),
            child: url == null ? Icon(AvatarHelper.getIcon(iconId), color: Colors.white) : null,
          ),
          title: Row(
            children: [
              Text(name),
              if (roleBadge != null) ...[SizedBox(width: 8), roleBadge!],
            ],
          ),
          subtitle: Text("@${(data['email'] ?? '').split('@')[0]}"),
          trailing: onEdit != null 
            ? IconButton(icon: Icon(Icons.edit, size: 16), onPressed: onEdit)
            : null,
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(userId: userId, includeScaffold: true)));
          },
        );
      },
    );
  }
}