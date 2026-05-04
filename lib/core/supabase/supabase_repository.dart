import '../../features/accounts/data/account_service.dart';
import '../../features/budgets/data/budget_service.dart';
import '../../features/categories/data/category_service.dart';
import '../../features/profile/application/profile_service.dart';
import '../../features/transactions/data/transaction_service.dart';
import 'supabase_service.dart';

final class SupabaseRepository {
  SupabaseRepository({required this.supabaseService})
    : profiles = ProfileService(supabaseService: supabaseService),
      accounts = AccountService(supabaseService: supabaseService),
      categories = CategoryService(supabaseService: supabaseService),
      budgets = BudgetService(supabaseService: supabaseService),
      transactions = TransactionService(supabaseService: supabaseService);

  final SupabaseService supabaseService;
  final ProfileService profiles;
  final AccountService accounts;
  final CategoryService categories;
  final BudgetService budgets;
  final TransactionService transactions;
}
