import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import 'dashboard_screen.dart';

/// Shown after the user picks a CSV; they must pick or create an account before import runs.
class AccountSelectionScreen extends StatelessWidget {
  const AccountSelectionScreen({
    super.key,
    required this.appState,
    required this.pendingCsvText,
  });

  final AppState appState;
  final String pendingCsvText;

  Future<void> _showAddAccountDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AddAccountDialog(
        onCreate: (name, type, balance) async {
          final account = Account(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            type: type,
            currentBalance: balance,
          );
          final ok = await appState.addAccount(account);
          if (!dialogContext.mounted) return;
          if (!ok) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('Could not save account.')),
            );
            return;
          }
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  Future<void> _importForAccount(BuildContext context, Account account) async {
    try {
      appState.loadFromCsv(pendingCsvText, accountId: account.id);
      if (!context.mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (context) => DashboardScreen(appState: appState),
        ),
      );
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
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final accounts = appState.accounts;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Choose account'),
            backgroundColor: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.surface,
                  theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                ],
              ),
            ),
            child: accounts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Add an account for this statement',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.75,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => _showAddAccountDialog(context),
                            child: const Text('Add account'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Text(
                          'Which account is this CSV for?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: accounts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final a = accounts[i];
                            return Material(
                              color: theme.colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                title: Text(a.name),
                                subtitle: Text(a.type.displayLabel),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                onTap: () => _importForAccount(context, a),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: OutlinedButton.icon(
                          onPressed: () => _showAddAccountDialog(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add account'),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog({required this.onCreate});

  final Future<void> Function(String name, AccountType type, double? balance)
  onCreate;

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  AccountType _type = AccountType.checking;
  var _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  double? _parseOptionalBalance(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t.replaceAll(',', ''));
    if (v == null || !v.isFinite) return null;
    return v;
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final balRaw = _balanceController.text;
    if (balRaw.trim().isNotEmpty) {
      final b = _parseOptionalBalance(balRaw);
      if (b == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a valid balance or leave it blank.')),
          );
        }
        return;
      }
    }
    final balance = _parseOptionalBalance(balRaw);
    setState(() => _saving = true);
    await widget.onCreate(name, _type, balance);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Bank of America Checking',
              ),
            ),
            const SizedBox(height: 8),
            Text('Type', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<AccountType>(
              segments: [
                for (final t in AccountType.values)
                  ButtonSegment<AccountType>(
                    value: t,
                    label: Text(
                      switch (t) {
                        AccountType.checking => 'Checking',
                        AccountType.savings => 'Savings',
                        AccountType.creditCard => 'Card',
                      },
                    ),
                  ),
              ],
              selected: {_type},
              onSelectionChanged: _saving
                  ? null
                  : (next) {
                      if (next.isNotEmpty) setState(() => _type = next.first);
                    },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Current balance (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
