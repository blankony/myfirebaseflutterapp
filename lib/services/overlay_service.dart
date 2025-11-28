import 'package:flutter/material.dart';
import 'dart:async';
import '../main.dart'; 

class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  OverlayEntry? _overlayEntry;
  Timer? _timer;

  void showTopNotification(BuildContext context, String message, IconData icon, VoidCallback onTap, {Color? color}) {
    // Remove existing overlay if any
    hideOverlay();

    OverlayState? overlayState = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => _TopNotificationWidget(
        message: message,
        icon: icon,
        iconColor: color,
        onTap: () {
          hideOverlay();
          onTap();
        },
        onDismiss: hideOverlay,
      ),
    );

    // Insert the entry into the overlay
    overlayState.insert(_overlayEntry!);

    // Auto-hide after 4 seconds
    _timer = Timer(const Duration(seconds: 4), () {
      hideOverlay();
    });
  }

  void hideOverlay() {
    _timer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _TopNotificationWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _TopNotificationWidget({
    required this.message,
    required this.icon,
    this.iconColor,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.only(top: topPadding + 10, left: 16, right: 16),
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.horizontal, // ENABLE SWIPE
              onDismissed: (direction) {
                widget.onDismiss();
              },
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDarkMode ? TwitterTheme.darkGrey : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(widget.icon, color: widget.iconColor ?? TwitterTheme.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      // Visual cue for dismissal
                      Container(
                        width: 4, 
                        height: 24,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(2)
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}