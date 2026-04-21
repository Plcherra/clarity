import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'account_detail_screen.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.appState});

  final AppState appState;

  Future<void> _showAddAccountDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AddAccountDialog(
        onCreate: (name, type, institution, balance) async {
          final account = Account(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            type: type,
            institution: institution,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final accounts = appState.accounts;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Accounts'),
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Add account',
                onPressed: () => _showAddAccountDialog(context),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          body: accounts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Add your first bank account',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.75),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () => _showAddAccountDialog(context),
                          child: const Text('Add account'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final a = accounts[i];
                    final inst = a.institution?.trim();
                    final subtitle = [
                      a.type.displayLabel,
                      if (inst != null && inst.isNotEmpty) inst,
                    ].join(' · ');
                    return Material(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(18),
                      child: ListTile(
                        title: Text(a.name),
                        subtitle: Text(subtitle),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (context) => AccountDetailScreen(
                                appState: appState,
                                accountId: a.id,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
          floatingActionButton: accounts.isEmpty
              ? null
              : FloatingActionButton(
                  onPressed: () => _showAddAccountDialog(context),
                  backgroundColor: cs.onSurface,
                  foregroundColor: cs.surface,
                  child: const Icon(Icons.add_rounded),
                ),
        );
      },
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog({required this.onCreate});

  final Future<void> Function(
    String name,
    AccountType type,
    String? institution,
    double? balance,
  ) onCreate;

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _nameController = TextEditingController();
  final _instController = TextEditingController();
  final _balanceController = TextEditingController();
  AccountType _type = AccountType.checking;
  var _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _instController.dispose();
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
    final inst = _instController.text.trim();
    final balance = _parseOptionalBalance(_balanceController.text);
    setState(() => _saving = true);
    await widget.onCreate(name, _type, inst.isEmpty ? null : inst, balance);
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
            const SizedBox(height: 10),
            TextField(
              controller: _instController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Institution (optional)',
                hintText: 'Capital One',
              ),
            ),
            const SizedBox(height: 12),
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
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

