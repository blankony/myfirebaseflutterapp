import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class NotificationPrefsService {
  static const String _keyHeadsUpEnabled = 'heads_up_notifications_enabled';
  static const String _keyAllNotificationsEnabled = 'all_notifications_enabled';

  // Notifiers for UI updates
  ValueNotifier<bool> headsUpEnabled = ValueNotifier(true);
  ValueNotifier<bool> allNotificationsEnabled = ValueNotifier(true);

  NotificationPrefsService() {
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    headsUpEnabled.value = prefs.getBool(_keyHeadsUpEnabled) ?? true;
    allNotificationsEnabled.value = prefs.getBool(_keyAllNotificationsEnabled) ?? true;
  }

  Future<void> setHeadsUp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHeadsUpEnabled, value);
    headsUpEnabled.value = value;
  }

  Future<void> setAllNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAllNotificationsEnabled, value);
    allNotificationsEnabled.value = value;
  }
}

// Global instance available throughout the app
final notificationPrefs = NotificationPrefsService();