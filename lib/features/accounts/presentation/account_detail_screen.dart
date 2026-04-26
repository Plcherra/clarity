import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../constants.dart';
import '../../../core/io/file_reader.dart';
import '../../../core/models/models.dart';
import '../../dashboard/domain/dashboard_snapshot.dart';
import '../../transactions/presentation/ai_category_review_screen.dart';
import '../../dashboard/presentation/financial_dashboard_view.dart';

class AccountDetailScreen extends StatelessWidget {
  const AccountDetailScreen({
    super.key,
    required this.appState,
    required this.accountId,
  });

  final AppState appState;
  final String accountId;

  Future<void> _importCsvForThisAccount(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: true,
      );
      if (!context.mounted) return;
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final text = await readPickedFileContents(file);
      if (!context.mounted) return;
      appState.loadFromCsv(text, accountId: accountId);
      if (!context.mounted) return;
      final unc = appState.uncategorizedImportedRowsForAccount(accountId);
      if (unc.isNotEmpty) {
        if (Constants.openAIKey.isEmpty) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Add OPENAI_API_KEY to your .env file to use AI categorization.',
              ),
            ),
          );
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'AI review: ${unc.length} '
                  'uncategorized transaction${unc.length == 1 ? '' : 's'}',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (ctx) => AiCategorizationFlowScreen(
                appState: appState,
                accountId: accountId,
                onFinished: () => Navigator.of(ctx).pop(),
              ),
            ),
          );
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported statement.')),
      );
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not import this file.')),
      );
    }
  }

  DashboardSnapshot _snapshotForAccount(AppState s) {
    final txs = List<Transaction>.unmodifiable(
      s.transactionsByAccount[accountId] ?? const [],
    );
    return buildDashboardSnapshot(
      scope: AccountDashboardScope(accountId),
      reference: s.spendReference,
      accounts: s.accounts,
      allTransactions: s.allTransactions,
      scopedTransactions: txs,
      categoryOverrides: s.categoryOverrides,
      categoryDisplayRenamesLower: s.categoryDisplayRenames,
      scopedBalanceFromStatement: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final account = appState.accounts
            .where((a) => a.id == accountId)
            .cast<Account?>()
            .firstWhere((a) => a != null, orElse: () => null);
        final title = account?.name ?? 'Account';
        return FinancialDashboardView(
          appState: appState,
          scope: AccountDashboardScope(accountId),
          showBackButton: true,
          title: title,
          buildSnapshot: (s, _) => _snapshotForAccount(s),
          onUploadTransactions: () => _importCsvForThisAccount(context),
        );
      },
    );
  }
}

