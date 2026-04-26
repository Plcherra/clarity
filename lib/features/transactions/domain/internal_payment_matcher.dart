import '../../../core/models/models.dart';

class ConfirmedPaymentMatch {
  const ConfirmedPaymentMatch({
    required this.source,
    required this.counterpart,
  });

  /// The transaction we are classifying (typically checking/savings outflow).
  final Transaction source;

  /// The opposite-side transaction (typically credit card inflow payment).
  final Transaction counterpart;
}

int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return (da.difference(db).inDays).abs();
}

bool _containsHint(String haystack, String needle) {
  final h = haystack.toLowerCase();
  final n = needle.toLowerCase().trim();
  if (n.isEmpty) return false;
  return h.contains(n);
}

bool _looksLikePaymentDescription(String description) {
  final h = description.toLowerCase();
  return h.contains('payment') ||
      h.contains('pmt') ||
      h.contains('paymt') ||
      h.contains('autopay') ||
      h.contains('online pmt') ||
      h.contains('thank you');
}

/// Attempts to confirm that [t] is an internal credit-card payment by finding a
/// counterpart payment row in a credit-card account.
///
/// Conservative by default: if no strong match exists, returns null so callers
/// keep treating [t] as an expense (prevents undercounting).
ConfirmedPaymentMatch? findConfirmedCreditCardPaymentMatch({
  required Transaction t,
  required List<Transaction> allTransactions,
  required Map<String, Account> accountsById,
  int maxDayDelta = 3,
}) {
  final srcAccount = accountsById[t.accountId];
  if (srcAccount == null) return null;
  if (srcAccount.type == AccountType.creditCard) return null;

  // v1: only attempt confirmation for outflows (money leaving funding account).
  if (t.amount >= 0) return null;

  final absAmount = t.amount.abs();
  if (!absAmount.isFinite || absAmount <= 0) return null;

  final desc = t.description;
  final hintedCreditCardAccountIds = <String>{};
  for (final a in accountsById.values) {
    if (a.type != AccountType.creditCard) continue;
    final inst = a.institution;
    final instHint =
        inst != null && inst.trim().isNotEmpty && _containsHint(desc, inst);
    final nameHint = _containsHint(desc, a.name);
    if (instHint || nameHint) hintedCreditCardAccountIds.add(a.id);
  }
  final hasSpecificCardHint = hintedCreditCardAccountIds.isNotEmpty;

  ConfirmedPaymentMatch? best;
  var bestScore = -1.0;

  for (final c in allTransactions) {
    if (c.accountId == t.accountId) continue;
    final target = accountsById[c.accountId];
    if (target == null || target.type != AccountType.creditCard) continue;
    if (hasSpecificCardHint && !hintedCreditCardAccountIds.contains(c.accountId)) {
      continue;
    }

    // Counterpart must be an inflow of the same magnitude.
    if (c.amount <= 0) continue;
    if ((c.amount - absAmount).abs() > 0.0001) continue;

    final dayDelta = _daysBetween(t.date, c.date);
    if (dayDelta > maxDayDelta) continue;

    // Scoring: prioritize amount+date+account types (already filtered), then hints.
    var score = 1.0;
    score += (maxDayDelta - dayDelta) * 0.2; // closer dates win

    final counterpartLooksLikePayment = _looksLikePaymentDescription(c.description);
    if (counterpartLooksLikePayment) score += 0.25;

    final inst = target.institution;
    final hasInstHint =
        inst != null && inst.trim().isNotEmpty && _containsHint(desc, inst);
    final hasNameHint = _containsHint(desc, target.name);

    if (hasInstHint) score += 0.45;
    if (hasNameHint) score += 0.35;

    if (score > bestScore) {
      bestScore = score;
      best = ConfirmedPaymentMatch(source: t, counterpart: c);
    }
  }

  return best;
}

