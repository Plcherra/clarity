import 'models.dart';

/// v1 fingerprint for dedupe within the same account.
///
/// Goal: stable across repeated imports of the same statement, without relying on
/// row index. Kept intentionally simple and explainable.
String transactionFingerprint(Transaction t) {
  final ba = t.balanceAfter;
  final desc = t.description.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return '${t.accountId}|${t.date.toIso8601String()}|${t.amount.toStringAsFixed(2)}|$desc|${ba ?? ''}';
}

