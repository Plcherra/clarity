import 'package:shared_preferences/shared_preferences.dart';

const String kRulesWipeMigrationDonePrefsKey = 'rules_wipe_migration_v1_done';

/// Removes persisted rule data from older versions of the app.
Future<void> runRulesWipeMigrationIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final done = prefs.getBool(kRulesWipeMigrationDonePrefsKey) ?? false;
  if (done) return;

  await prefs.remove('category_rules_v1');
  await prefs.setBool(kRulesWipeMigrationDonePrefsKey, true);
}

