import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'budget_keys.dart';

/// Legacy SharedPreferences key for the flat category->amount map.
const String kCategoryMonthlyBudgetsPrefsKey = 'category_monthly_budgets_v1';

/// SharedPreferences key for the month-aware budget map (year-month -> category->amount).
const String kCategoryMonthlyBudgetsByMonthPrefsKey = 'category_monthly_budgets_v2';
const String kCategoryBudgetsStorePrefsKey = 'category_budgets_store_v3';

class BudgetStorageRange {
  const BudgetStorageRange({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;
}

class BudgetStorageSnapshot {
  const BudgetStorageSnapshot({
    required this.monthly,
    required this.weekly,
    required this.custom,
    required this.customRanges,
  });

  final Map<String, Map<String, double>> monthly;
  final Map<String, Map<String, double>> weekly;
  final Map<String, Map<String, double>> custom;
  final Map<String, BudgetStorageRange> customRanges;
}

String _yearMonthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

bool _isYearMonthKey(String value) {
  final parts = value.split('-');
  if (parts.length != 2) return false;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  return y != null && m != null && m >= 1 && m <= 12;
}

double? _asValidAmount(Object? value) {
  final amount = switch (value) {
    int i => i.toDouble(),
    double d => d,
    _ => null,
  };
  if (amount == null || !amount.isFinite || amount < 0) return null;
  return amount;
}

Map<String, double> _parseFlatBudgetMap(dynamic decoded) {
  if (decoded is! Map) return {};
  final out = <String, double>{};
  for (final e in decoded.entries) {
    final k = e.key;
    if (k is! String) continue;
    final key = budgetDisplayKey(k);
    if (key.isEmpty) continue;
    final amount = _asValidAmount(e.value);
    if (amount == null) continue;
    out[key] = amount;
  }
  return out;
}

Map<String, Map<String, double>> _parseBudgetsByMonth(dynamic decoded) {
  if (decoded is! Map) return {};
  final out = <String, Map<String, double>>{};
  for (final e in decoded.entries) {
    final month = e.key;
    if (month is! String || !_isYearMonthKey(month)) continue;
    final categories = _parseFlatBudgetMap(e.value);
    if (categories.isEmpty) continue;
    out[month] = categories;
  }
  return out;
}

Map<String, Map<String, double>> _parseBudgetsByDateKey(dynamic decoded) {
  if (decoded is! Map) return {};
  final out = <String, Map<String, double>>{};
  for (final e in decoded.entries) {
    final key = e.key;
    if (key is! String || _parseDateKey(key) == null) continue;
    final categories = _parseFlatBudgetMap(e.value);
    if (categories.isEmpty) continue;
    out[key] = categories;
  }
  return out;
}

DateTime? _parseDateKey(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Map<String, BudgetStorageRange> _parseCustomRanges(dynamic decoded) {
  if (decoded is! Map) return {};
  final out = <String, BudgetStorageRange>{};
  for (final e in decoded.entries) {
    final key = e.key;
    if (key is! String) continue;
    final v = e.value;
    if (v is! Map) continue;
    final startRaw = v['start'];
    final endRaw = v['end'];
    if (startRaw is! String || endRaw is! String) continue;
    final start = _parseDateKey(startRaw);
    final end = _parseDateKey(endRaw);
    if (start == null || end == null) continue;
    final lo = start.isBefore(end) ? start : end;
    final hi = start.isBefore(end) ? end : start;
    out[key] = BudgetStorageRange(start: lo, end: hi);
  }
  return out;
}

Map<String, Map<String, double>> _parseBudgetMapSection(dynamic decoded) {
  if (decoded is! Map) return {};
  final out = <String, Map<String, double>>{};
  for (final e in decoded.entries) {
    final key = e.key;
    if (key is! String) continue;
    final categories = _parseFlatBudgetMap(e.value);
    if (categories.isEmpty) continue;
    out[key] = categories;
  }
  return out;
}

/// Loads persisted month-aware budgets.
///
/// Keys are `YYYY-MM` strings and category maps keyed by [budgetDisplayKey].
/// If only the legacy flat map exists, it is loaded into the current month.
Future<BudgetStorageSnapshot> loadBudgetSnapshot({
  DateTime? reference,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final rawV3 = prefs.getString(kCategoryBudgetsStorePrefsKey);
  if (rawV3 != null && rawV3.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawV3);
      if (decoded is Map) {
        final monthly = _parseBudgetsByMonth(decoded['monthly']);
        final weekly = _parseBudgetsByDateKey(decoded['weekly']);
        final custom = _parseBudgetMapSection(decoded['custom']);
        final customRanges = _parseCustomRanges(decoded['customRanges']);
        return BudgetStorageSnapshot(
          monthly: monthly,
          weekly: weekly,
          custom: custom,
          customRanges: customRanges,
        );
      }
    } on Object {
      // Ignore malformed v3 payload and attempt older fallbacks.
    }
  }

  final rawV2 = prefs.getString(kCategoryMonthlyBudgetsByMonthPrefsKey);
  if (rawV2 != null && rawV2.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawV2);
      final byMonth = _parseBudgetsByMonth(decoded);
      if (byMonth.isNotEmpty) {
        return BudgetStorageSnapshot(
          monthly: byMonth,
          weekly: const {},
          custom: const {},
          customRanges: const {},
        );
      }
    } on Object {
      // Ignore malformed v2 payload and attempt legacy fallback.
    }
  }

  final rawV1 = prefs.getString(kCategoryMonthlyBudgetsPrefsKey);
  if (rawV1 == null || rawV1.isEmpty) {
    return const BudgetStorageSnapshot(
      monthly: {},
      weekly: {},
      custom: {},
      customRanges: {},
    );
  }

  dynamic decoded;
  try {
    decoded = jsonDecode(rawV1);
  } on Object {
    return const BudgetStorageSnapshot(
      monthly: {},
      weekly: {},
      custom: {},
      customRanges: {},
    );
  }
  final flat = _parseFlatBudgetMap(decoded);
  if (flat.isEmpty) {
    return const BudgetStorageSnapshot(
      monthly: {},
      weekly: {},
      custom: {},
      customRanges: {},
    );
  }

  final ref = reference ?? DateTime.now();
  return BudgetStorageSnapshot(
    monthly: {_yearMonthKey(ref): flat},
    weekly: const {},
    custom: const {},
    customRanges: const {},
  );
}

Map<String, Map<String, double>> _sanitizeBudgetMapSection(
  Map<String, Map<String, double>> raw,
) {
  final out = <String, Map<String, double>>{};
  for (final section in raw.entries) {
    final key = section.key.trim();
    if (key.isEmpty) continue;
    final byCategory = <String, double>{};
    for (final e in section.value.entries) {
      final categoryKey = budgetDisplayKey(e.key);
      final amount = e.value;
      if (categoryKey.isEmpty || !amount.isFinite || amount < 0) continue;
      byCategory[categoryKey] = amount;
    }
    if (byCategory.isEmpty) continue;
    out[key] = byCategory;
  }
  return out;
}

Future<void> saveBudgetSnapshot(BudgetStorageSnapshot snapshot) async {
  final prefs = await SharedPreferences.getInstance();
  final monthlyRaw = _sanitizeBudgetMapSection(snapshot.monthly);
  final monthly = <String, Map<String, double>>{};
  for (final e in monthlyRaw.entries) {
    if (_isYearMonthKey(e.key)) monthly[e.key] = e.value;
  }
  final weeklyRaw = _sanitizeBudgetMapSection(snapshot.weekly);
  final weekly = <String, Map<String, double>>{};
  for (final e in weeklyRaw.entries) {
    if (_parseDateKey(e.key) != null) weekly[e.key] = e.value;
  }
  final custom = _sanitizeBudgetMapSection(snapshot.custom);

  final customRanges = <String, Map<String, String>>{};
  for (final e in snapshot.customRanges.entries) {
    final key = e.key.trim();
    if (key.isEmpty) continue;
    final start = DateTime(
      e.value.start.year,
      e.value.start.month,
      e.value.start.day,
    );
    final end = DateTime(
      e.value.end.year,
      e.value.end.month,
      e.value.end.day,
    );
    final lo = start.isBefore(end) ? start : end;
    final hi = start.isBefore(end) ? end : start;
    customRanges[key] = {
      'start': _dateKey(lo),
      'end': _dateKey(hi),
    };
  }

  final json = jsonEncode({
    'monthly': monthly,
    'weekly': weekly,
    'custom': custom,
    'customRanges': customRanges,
  });
  await prefs.setString(kCategoryBudgetsStorePrefsKey, json);
}

