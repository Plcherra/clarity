import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const String kTransactionsByAccountPrefsKey = 'transactions_by_account_v1';

String _roleToWire(FinancialRole r) => switch (r) {
      FinancialRole.expense => 'expense',
      FinancialRole.income => 'income',
      FinancialRole.transfer => 'transfer',
      FinancialRole.creditCardPayment => 'creditCardPayment',
      FinancialRole.refund => 'refund',
      FinancialRole.adjustment => 'adjustment',
    };

FinancialRole? _roleFromWire(Object? raw) => switch (raw) {
      'expense' => FinancialRole.expense,
      'income' => FinancialRole.income,
      'transfer' => FinancialRole.transfer,
      'creditCardPayment' => FinancialRole.creditCardPayment,
      'refund' => FinancialRole.refund,
      'adjustment' => FinancialRole.adjustment,
      _ => null,
    };

Map<String, dynamic> _txToJson(Transaction t) => {
  'date': t.date.toIso8601String(),
  'description': t.description,
  'amount': t.amount,
  'accountId': t.accountId,
  if (t.category != null) 'category': t.category,
  if (t.balanceAfter != null) 'balanceAfter': t.balanceAfter,
  if (t.categoryId != null) 'categoryId': t.categoryId,
  if (t.importId != null) 'importId': t.importId,
  if (t.fingerprint != null) 'fingerprint': t.fingerprint,
  if (t.financialRole != null) 'financialRole': _roleToWire(t.financialRole!),
};

Transaction? _txFromJson(Object? raw) {
  if (raw is! Map) return null;
  final dateRaw = raw['date'];
  final desc = raw['description'];
  final amt = raw['amount'];
  final acct = raw['accountId'];
  if (dateRaw is! String || desc is! String || acct is! String) return null;
  if (amt is! num) return null;
  final date = DateTime.tryParse(dateRaw);
  if (date == null) return null;
  final amount = amt.toDouble();
  if (!amount.isFinite) return null;

  final category = raw['category'];
  final balanceAfter = raw['balanceAfter'];
  final categoryId = raw['categoryId'];
  final importId = raw['importId'];
  final fingerprint = raw['fingerprint'];
  final role = _roleFromWire(raw['financialRole']);

  final b = balanceAfter is num ? balanceAfter.toDouble() : null;
  final bOk = b != null && b.isFinite ? b : null;

  return Transaction(
    date: DateTime(date.year, date.month, date.day, 12),
    description: desc,
    amount: amount,
    accountId: acct,
    category: category is String ? category : null,
    balanceAfter: bOk,
    categoryId: categoryId is String ? categoryId : null,
    importId: importId is String ? importId : null,
    fingerprint: fingerprint is String ? fingerprint : null,
    financialRole: role,
  );
}

Future<Map<String, List<Transaction>>> loadTransactionsByAccount() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kTransactionsByAccountPrefsKey);
  if (raw == null || raw.isEmpty) return {};

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    return {};
  }
  if (decoded is! Map) return {};

  final out = <String, List<Transaction>>{};
  for (final e in decoded.entries) {
    final accountId = e.key;
    final v = e.value;
    if (accountId is! String || accountId.trim().isEmpty) continue;
    if (v is! List) continue;
    final list = <Transaction>[];
    for (final item in v) {
      final t = _txFromJson(item);
      if (t != null) list.add(t);
    }
    out[accountId.trim()] = list;
  }
  return out;
}

Future<void> saveTransactionsByAccount(
  Map<String, List<Transaction>> map,
) async {
  final prefs = await SharedPreferences.getInstance();
  final serializable = <String, dynamic>{};
  for (final e in map.entries) {
    final accountId = e.key.trim();
    if (accountId.isEmpty) continue;
    serializable[accountId] = e.value.map(_txToJson).toList();
  }
  await prefs.setString(
    kTransactionsByAccountPrefsKey,
    jsonEncode(serializable),
  );
}

