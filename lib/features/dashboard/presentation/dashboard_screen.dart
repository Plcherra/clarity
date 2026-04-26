import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../domain/dashboard_snapshot.dart';
import 'financial_dashboard_view.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.appState, this.isRoot = false});

  final AppState appState;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    return FinancialDashboardView(
      appState: appState,
      scope: const GlobalDashboardScope(),
      showBackButton: !isRoot,
      title: 'Overview',
      buildSnapshot: (s, scope) {
        return buildDashboardSnapshot(
          scope: const GlobalDashboardScope(),
          reference: s.spendReference,
          accounts: s.accounts,
          allTransactions: s.allTransactions,
          scopedTransactions: s.allTransactions,
          categoryOverrides: s.categoryOverrides,
          categoryDisplayRenamesLower: s.categoryDisplayRenames,
          categoryRules: s.categoryRules,
          scopedBalanceFromStatement: null,
        );
      },
    );
  }
}

