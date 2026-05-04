import 'dart:async';

import '../core/supabase/supabase_exceptions.dart';
import '../features/accounts/application/account_service.dart';
import '../features/auth/application/auth_service.dart';
import '../features/budgets/application/budget_service.dart';
import '../features/categories/application/category_read_model.dart';
import '../features/categories/application/category_service.dart';
import '../features/transactions/application/transaction_service.dart';

class AppStartupService {
  AppStartupService({
    required this.authService,
    required this.budgetService,
    required this.accountService,
    required this.categoryService,
    required this.categoryReadModel,
    required this.transactionService,
    required this.notifyDashboardAndBudgetsChanged,
    required this.notifyAccountsChanged,
    required this.notifyTransactionDataChanged,
  });

  final AuthService authService;
  final BudgetService budgetService;
  final AccountService accountService;
  final CategoryService categoryService;
  final CategoryReadModel categoryReadModel;
  final TransactionService transactionService;
  final void Function() notifyDashboardAndBudgetsChanged;
  final void Function() notifyAccountsChanged;
  final void Function() notifyTransactionDataChanged;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  StreamSubscription<dynamic>? _authSubscription;

  Future<void> hydrateForStartup() async {
    _startAuthWatcher();
    await _fetchInitialSupabaseData();
    _startSupabaseWatchers();
  }

  Future<void> _fetchInitialSupabaseData() async {
    final accountsLoaded = await _runIfAuthenticated(
      accountService.fetchAccounts,
    );
    if (accountsLoaded) notifyAccountsChanged();

    final budgetsLoaded = await _runIfAuthenticated(budgetService.fetchBudgets);
    if (budgetsLoaded) notifyDashboardAndBudgetsChanged();

    final categoriesLoaded = await _runIfAuthenticated(
      categoryReadModel.refresh,
    );
    if (categoriesLoaded) notifyTransactionDataChanged();

    final transactionsLoaded = await _runIfAuthenticated(
      transactionService.fetchTransactions,
    );
    if (transactionsLoaded) notifyTransactionDataChanged();
  }

  void _startSupabaseWatchers() {
    if (_subscriptions.isNotEmpty) return;

    _listenIfAuthenticated(
      accountService.watchAccounts,
      (_) => notifyAccountsChanged(),
    );
    _listenIfAuthenticated(
      budgetService.watchBudgets,
      (_) => notifyDashboardAndBudgetsChanged(),
    );
    try {
      categoryReadModel.startWatching(
        onChanged: () {
          notifyDashboardAndBudgetsChanged();
          notifyTransactionDataChanged();
        },
      );
    } on SupabaseAuthRequiredException {
      return;
    }
    _listenIfAuthenticated(
      transactionService.watchTransactions,
      (_) => notifyTransactionDataChanged(),
    );
  }

  void _startAuthWatcher() {
    _authSubscription ??= authService.authStateChanges.listen((_) async {
      if (authService.currentUser == null) {
        _stopSupabaseWatchers();
        categoryReadModel.stopWatching();
        notifyAccountsChanged();
        notifyDashboardAndBudgetsChanged();
        notifyTransactionDataChanged();
        return;
      }

      await _fetchInitialSupabaseData();
      _startSupabaseWatchers();
    });
  }

  Future<bool> _runIfAuthenticated(Future<Object?> Function() action) async {
    try {
      await action();
      return true;
    } on SupabaseAuthRequiredException {
      return false;
    }
  }

  void _listenIfAuthenticated(
    Stream<Object?> Function() streamFactory,
    void Function(Object?) onData,
  ) {
    try {
      _subscriptions.add(streamFactory().listen(onData));
    } on SupabaseAuthRequiredException {
      return;
    }
  }

  void dispose() {
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    _stopSupabaseWatchers();
  }

  void _stopSupabaseWatchers() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    categoryReadModel.stopWatching();
  }
}
