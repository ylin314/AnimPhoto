import 'package:shared_preferences/shared_preferences.dart';

const String kMultiSelectUsedKey = 'animphoto.guide.multi_select_used';
const String kMultiSelectActionsGuideCompletedKey =
    'animphoto.guide.multi_select_actions_completed';
const String kPhotoMenuGuideCompletedKey =
    'animphoto.guide.photo_menu_completed';

Future<bool> isFeatureGuideCompleted(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(key) ?? false;
}

Future<void> markFeatureGuideCompleted(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(key, true);
}
