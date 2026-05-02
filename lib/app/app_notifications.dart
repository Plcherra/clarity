import 'ui_dependencies.dart';

final class AppNotifications {
  const AppNotifications({required this.ui});

  final AppUiDependencies ui;

  void dashboardAndBudgetsChanged() {
    ui.notifyDashboard();
    ui.notifyBudgets();
  }

  void categoryCatalogChanged() {
    ui.notifyTransactions();
    ui.notifyBudgets();
    ui.notifyDashboard();
  }

  void accountsChanged() {
    ui.notifyAccounts();
    ui.notifyDashboard();
  }

  void transactionDataChanged() {
    ui.notifyDataChanged();
  }

  void importAiStatusChanged() {
    ui.notifyImportAiStatus();
  }
}
