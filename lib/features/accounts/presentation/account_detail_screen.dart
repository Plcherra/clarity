import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import '../../../core/io/file_reader.dart';
import '../../../core/models/models.dart';
import '../../transactions/data/csv_import_service.dart';
import '../../dashboard/domain/dashboard_snapshot.dart';
import '../../dashboard/presentation/financial_dashboard_view.dart';

class AccountDetailScreen extends StatelessWidget {
  const AccountDetailScreen({
    super.key,
    required this.controller,
    required this.accountId,
  });

  final AccountUiController controller;
  final String accountId;

  String _batchLabel(CsvImportBatchSummary batch) {
    final utc = batch.importedAtUtc;
    if (utc == null) return 'Upload ${batch.importId}';
    final local = utc.toLocal();
    final yy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$yy-$mm-$dd $hh:$min';
  }

  Future<void> _deleteCsvUploadBatch(BuildContext context) async {
    final batches = controller.csvImportBatchesForAccount(accountId);
    if (batches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No CSV uploads found for this account.')),
      );
      return;
    }

    final selected = await showDialog<CsvImportBatchSummary>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Delete CSV upload'),
        children: [
          for (final batch in batches)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(batch),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _batchLabel(batch),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${batch.transactionCount} transaction${batch.transactionCount == 1 ? '' : 's'}',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this CSV upload?'),
        content: Text(
          'Delete ${selected.transactionCount} transaction'
          '${selected.transactionCount == 1 ? '' : 's'} from this upload? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete upload'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final deleted = await controller.deleteTransactionsForImportBatch(
      accountId: accountId,
      importId: selected.importId,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted > 0
              ? 'Deleted $deleted transaction${deleted == 1 ? '' : 's'} from CSV upload.'
              : 'Could not delete CSV upload.',
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, String accountName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'Delete this account and all its transactions? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await controller.deleteAccount(accountId);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete account.')),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$accountName deleted.')));
    Navigator.of(context).pop();
  }

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
      controller.loadFromCsv(text, accountId: accountId);
      if (!context.mounted) return;
      if (controller.needsImportAiAfterCsvUpload(accountId)) {
        if (!controller.importAiEngineConfigured) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sign in and configure the Supabase AI Edge Function secret to use AI categorization.',
              ),
            ),
          );
        } else {
          unawaited(
            controller.startBackgroundImportAiCategorization(accountId),
          );
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Imported statement.')));
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not import this file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final account = controller.accounts
            .where((a) => a.id == accountId)
            .cast<Account?>()
            .firstWhere((a) => a != null, orElse: () => null);
        final title = account?.name ?? 'Account';
        return FinancialDashboardView(
          controller: controller.ui.dashboard,
          scope: AccountDashboardScope(accountId),
          showBackButton: true,
          title: title,
          buildSnapshot: (_, _) =>
              controller.buildSnapshotForAccount(accountId),
          onUploadTransactions: () => _importCsvForThisAccount(context),
          onDeleteCsvImportBatch: () => _deleteCsvUploadBatch(context),
          onDeleteAccount: () => _deleteAccount(context, title),
        );
      },
    );
  }
}
