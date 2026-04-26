import 'core/models/models.dart';

/// Stable identity key for dedupe within the same account.
///
/// Goal: stable across repeated imports of the same statement, without relying on
/// row index or running balance columns (which can be missing or inconsistent).
String transactionFingerprint(Transaction t) {
  final desc = t.description
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  final y = t.date.year.toString().padLeft(4, '0');
  final m = t.date.month.toString().padLeft(2, '0');
  final d = t.date.day.toString().padLeft(2, '0');
  final dayKey = '$y-$m-$d';
  return '${t.accountId}|$dayKey|${t.amount.toStringAsFixed(2)}|$desc';
}

