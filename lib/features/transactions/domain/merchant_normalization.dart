/// Deterministic normalization from raw bank description -> stable merchant key.
///
/// This intentionally starts simple and can be refined as we see real data.
/// The goal is consistency across months (e.g. `Planet Fitness` rows normalize
/// to the same key) rather than perfect merchant extraction.
String merchantKeyLowerFromDescription(String description) {
  var s = description.trim().toLowerCase();
  if (s.isEmpty) return '';

  // Replace punctuation with spaces, keep letters/numbers.
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');

  // Drop common banking noise tokens (whole words).
  const noise = <String>{
    'pos',
    'debit',
    'credit',
    'purchase',
    'purchased',
    'card',
    'visa',
    'mastercard',
    'mc',
    'ach',
    'auth',
    'online',
    'recurring',
    'payment',
    'withdrawal',
    'transfer',
    'txn',
  };

  final parts = s.split(RegExp(r'\s+'));
  final kept = <String>[];
  for (final p in parts) {
    final t = p.trim();
    if (t.isEmpty) continue;
    if (noise.contains(t)) continue;

    // Drop long digit runs that are typically references / auth codes.
    if (RegExp(r'^\d{4,}$').hasMatch(t)) continue;
    kept.add(t);
  }

  // Collapse multiple spaces.
  return kept.join(' ').trim();
}

