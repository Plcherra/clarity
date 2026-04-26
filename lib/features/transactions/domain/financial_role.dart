import '../../../core/models/models.dart';
import 'internal_payment_matcher.dart';
import 'spend_categories.dart';

bool _looksLikeRefundDescription(String description) {
  final h = description.toLowerCase();
  return h.contains('refund') ||
      h.contains('refunded') ||
      h.contains('reversal') ||
      h.contains('reversed') ||
      h.contains('chargeback');
}

/// Derives the effective financial role used for dashboards.
///
/// Direction is one-way: role resolution may call matchers, but matchers must
/// not call role resolution (prevents recursion).
FinancialRole effectiveFinancialRole({
  required Transaction t,
  required String effectiveCategoryLabel,
  required Map<String, Account> accountsById,
  required List<Transaction> allTransactions,
}) {
  final stored = t.financialRole;
  if (stored != null) return stored;

  if (isIgnoredCategoryLabel(effectiveCategoryLabel)) {
    return FinancialRole.adjustment;
  }

  // Refunds are a distinct role (v1 policy: exclude from both income and spend).
  if (t.amount > 0 && _looksLikeRefundDescription(t.description)) {
    return FinancialRole.refund;
  }

  if (effectiveCategoryLabel.trim().toLowerCase() == 'transfer out') {
    return FinancialRole.transfer;
  }

  // Credit card payment: confirm by finding the opposite-side payment row.
  if (effectiveCategoryLabel.trim().toLowerCase() ==
      'credit card payment'.toLowerCase()) {
    final match = findConfirmedCreditCardPaymentMatch(
      t: t,
      allTransactions: allTransactions,
      accountsById: accountsById,
    );
    if (match != null) return FinancialRole.creditCardPayment;
    return FinancialRole.expense; // conservative until confirmed
  }

  if (isIncomeCategoryLabel(effectiveCategoryLabel)) {
    return FinancialRole.income;
  }

  // Fallback by sign.
  if (t.amount < 0) return FinancialRole.expense;
  if (t.amount > 0) return FinancialRole.income;
  return FinancialRole.adjustment;
}

