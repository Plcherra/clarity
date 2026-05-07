import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import 'import_job_progress_banner.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../budgets/presentation/budgets_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.ui, this.signOut});

  final AppUiDependencies ui;
  final Future<void> Function()? signOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final pages = <Widget>[
      DashboardScreen(controller: widget.ui.dashboard, isRoot: true),
      AccountsScreen(controller: widget.ui.accounts),
      BudgetsScreen(controller: widget.ui.budgets),
    ];

    return Scaffold(
      body: ImportJobStatusHost(
        controller: widget.ui.importJobStatus,
        child: IndexedStack(index: _idx, children: pages),
      ),
      floatingActionButton: widget.signOut == null
          ? null
          : FloatingActionButton.small(
              tooltip: 'Sign out',
              onPressed: widget.signOut,
              child: const Icon(Icons.logout_rounded),
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance_rounded),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings_rounded),
            label: 'Budgets',
          ),
        ],
      ),
    );
  }
}
