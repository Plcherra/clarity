import 'package:flutter/material.dart';

import '../app_state.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.appState});

  final AppState appState;

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
      DashboardScreen(appState: widget.appState, isRoot: true),
      AccountsScreen(appState: widget.appState),
      BudgetsScreen(appState: widget.appState),
    ];

    return Scaffold(
      body: IndexedStack(index: _idx, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: cs.surface,
        indicatorColor: cs.surfaceContainerHighest.withValues(alpha: 0.65),
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

