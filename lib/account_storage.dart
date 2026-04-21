import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const String kAccountsPrefsKey = 'accounts_v1';

String _accountTypeToWire(AccountType t) => switch (t) {
      AccountType.checking => 'checking',
      AccountType.savings => 'savings',
      AccountType.creditCard => 'creditCard',
    };

AccountType? _accountTypeFromWire(String? raw) => switch (raw) {
      'checking' => AccountType.checking,
      'savings' => AccountType.savings,
      'creditCard' => AccountType.creditCard,
      _ => null,
    };

/// Loads persisted accounts (best-effort; skips malformed entries).
Future<List<Account>> loadAccounts() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kAccountsPrefsKey);
  if (raw == null || raw.isEmpty) return [];

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return [];
  }
  if (decoded is! List) return [];

  final out = <Account>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    final id = e['id'];
    final name = e['name'];
    final typeRaw = e['type'];
    final instRaw = e['institution'];
    if (id is! String || id.trim().isEmpty) continue;
    if (name is! String || name.trim().isEmpty) continue;
    final type = _accountTypeFromWire(typeRaw is String ? typeRaw : null);
    if (type == null) continue;

    double? balance;
    final b = e['currentBalance'];
    if (b is num) {
      final d = b.toDouble();
      if (d.isFinite) balance = d;
    }

    out.add(
      Account(
        id: id.trim(),
        name: name.trim(),
        type: type,
        institution: instRaw is String && instRaw.trim().isNotEmpty
            ? instRaw.trim()
            : null,
        currentBalance: balance,
      ),
    );
  }
  return out;
}

Future<void> saveAccounts(List<Account> accounts) async {
  final prefs = await SharedPreferences.getInstance();
  final list = <Map<String, dynamic>>[];
  for (final a in accounts) {
    list.add({
      'id': a.id,
      'name': a.name,
      'type': _accountTypeToWire(a.type),
      if (a.institution != null && a.institution!.trim().isNotEmpty)
        'institution': a.institution!.trim(),
      if (a.currentBalance != null) 'currentBalance': a.currentBalance,
    });
  }
  await prefs.setString(kAccountsPrefsKey, jsonEncode(list));
}
