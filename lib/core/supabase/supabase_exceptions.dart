class SupabaseDataException implements Exception {
  const SupabaseDataException({
    required this.table,
    required this.action,
    required this.message,
    this.cause,
  });

  final String table;
  final String action;
  final String message;
  final Object? cause;

  @override
  String toString() => 'SupabaseDataException($table.$action): $message';
}

class SupabaseAuthRequiredException extends SupabaseDataException {
  const SupabaseAuthRequiredException()
    : super(
        table: 'auth',
        action: 'currentUser',
        message: 'A signed-in Supabase user is required.',
      );
}
