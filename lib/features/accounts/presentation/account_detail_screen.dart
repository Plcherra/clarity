import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/ui_dependencies.dart';
import '../../../core/io/file_reader.dart';
import '../../../core/models/models.dart';
import '../../transactions/data/csv_import_service.dart';
import '../../dashboard/domain/dashboard_snapshot.dart';
import '../../dashboard/presentation/financial_dashboard_view.dart';

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({
    super.key,
    required this.controller,
    required this.accountId,
  });

  final AccountUiController controller;
  final String accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  late final _AccountDetailDataNotifier _dataNotifier;
  var _deletingCsvUpload = false;

  @override
  void initState() {
    super.initState();
    _dataNotifier = _AccountDetailDataNotifier();
    widget.controller.addListener(_handleControllerChanged);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant AccountDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.accountId != widget.accountId) {
      _loadData();
    }
  }

  void _handleControllerChanged() {
    _loadData();
  }

  Future<void> _loadData() async {
    _dataNotifier.setLoading();
    try {
      final accounts = await widget.controller.accounts;
      if (!mounted) return;
      _dataNotifier.setData(accounts);
    } on Object catch (error) {
      if (!mounted) return;
      _dataNotifier.setError(error);
    }
  }

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
    if (_deletingCsvUpload) return;

    final batches = await widget.controller.csvImportBatchesForAccount(
      widget.accountId,
    );
    if (!context.mounted) return;
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

    setState(() => _deletingCsvUpload = true);
    var deleted = 0;
    Object? error;
    var progressDialogShown = false;
    if (context.mounted) {
      progressDialogShown = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const _CsvUploadDeletingDialog(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    try {
      deleted = await widget.controller.deleteTransactionsForImportBatch(
        accountId: widget.accountId,
        importId: selected.importId,
      );
    } on Object catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => _deletingCsvUpload = false);
      if (progressDialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete CSV upload.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted > 0
              ? 'Deleted $deleted transaction${deleted == 1 ? '' : 's'} from CSV upload.'
              : 'CSV upload was already deleted.',
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

    final ok = await widget.controller.deleteAccount(widget.accountId);
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
      final result = await FilePicker.pickFiles(
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
      await widget.controller.loadFromCsv(text, accountId: widget.accountId);
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
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _dataNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _dataNotifier,
      builder: (context, _) {
        final accounts = _dataNotifier.data;
        if (accounts == null) {
          if (_dataNotifier.error != null) {
            return const Scaffold(
              body: Center(child: Text('Could not load account.')),
            );
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final account = accounts
            .where((a) => a.id == widget.accountId)
            .cast<Account?>()
            .firstWhere((a) => a != null, orElse: () => null);
        final title = account?.name ?? 'Account';
        return FinancialDashboardView(
          controller: widget.controller.ui.dashboard,
          scope: AccountDashboardScope(widget.accountId),
          showBackButton: true,
          title: title,
          buildSnapshot: (_, _) =>
              widget.controller.buildSnapshotForAccount(widget.accountId),
          onUploadTransactions: () => _importCsvForThisAccount(context),
          onDeleteCsvImportBatch: _deletingCsvUpload
              ? null
              : () => _deleteCsvUploadBatch(context),
          onDeleteAccount: () => _deleteAccount(context, title),
        );
      },
    );
  }
}

class _CsvUploadDeletingDialog extends StatelessWidget {
  const _CsvUploadDeletingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 20),
          Expanded(child: Text('Deleting CSV upload...')),
        ],
      ),
    );
  }
}

class _AccountDetailDataNotifier extends ChangeNotifier {
  List<Account>? _data;
  Object? _error;
  var _loading = false;

  List<Account>? get data => _data;
  Object? get error => _error;
  bool get loading => _loading;

  void setLoading() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void setData(List<Account> data) {
    _data = data;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  void setError(Object error) {
    _error = error;
    _loading = false;
    notifyListeners();
  }
}
