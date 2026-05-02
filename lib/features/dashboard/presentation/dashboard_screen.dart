import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import '../domain/dashboard_snapshot.dart';
import 'financial_dashboard_view.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    this.isRoot = false,
  });

  final DashboardUiController controller;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    return FinancialDashboardView(
      controller: controller,
      scope: const GlobalDashboardScope(),
      showBackButton: !isRoot,
      title: 'Overview',
      buildSnapshot: (controller, scope) => controller.buildSnapshot(scope),
    );
  }
}
