import 'package:flutter/material.dart';

import '../app_state.dart';
import '../category_description_normalize.dart';
import '../models.dart';
import '../spend_categories.dart';

/// Minimum length for a saved description rule pattern (after normalization).
const int kMinCategoryRulePatternLength = 3;

/// After assigning an outflow category, offers to persist a contains-rule.
Future<void> showSaveCategoryRuleDialogIfOutflow({
  required BuildContext context,
  required AppState appState,
  required Transaction transaction,
  required String categoryCanonical,
}) async {
  if (!transaction.isOutflow) return;
  if (!context.mounted) return;

  final suggested = suggestedPatternFromDescription(transaction.description);

  final raw = await showDialog<String?>(
    context: context,
    builder: (ctx) => _SaveCategoryRuleDialog(
      suggested: suggested,
      categoryCanonical: categoryCanonical,
    ),
  );

  if (raw == null || !context.mounted) return;

  if (raw.length < kMinCategoryRulePatternLength) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pattern must be at least $kMinCategoryRulePatternLength characters.',
        ),
      ),
    );
    return;
  }

  final ok = await appState.addOrUpdateCategoryRuleByPattern(
    raw,
    categoryCanonical,
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save rule. Try again.')),
    );
  }
}

class _SaveCategoryRuleDialog extends StatefulWidget {
  const _SaveCategoryRuleDialog({
    required this.suggested,
    required this.categoryCanonical,
  });

  final String suggested;
  final String categoryCanonical;

  @override
  State<_SaveCategoryRuleDialog> createState() =>
      _SaveCategoryRuleDialogState();
}

class _SaveCategoryRuleDialogState extends State<_SaveCategoryRuleDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.suggested);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save a rule?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Apply "${widget.categoryCanonical}" to future outflows whose description contains:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. nero',
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save rule'),
        ),
      ],
    );
  }
}

/// Inline category menu below the chip: no dimming modal, transparent outside tap to close.
class TransactionCategoryField extends StatefulWidget {
  const TransactionCategoryField({
    super.key,
    required this.appState,
    required this.transaction,
    required this.displayCategory,
  });

  final AppState appState;
  final Transaction transaction;
  final String displayCategory;

  @override
  State<TransactionCategoryField> createState() =>
      _TransactionCategoryFieldState();
}

class _TransactionCategoryFieldState extends State<TransactionCategoryField> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _openOverlay() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    final overlayState = Overlay.maybeOf(context);
    if (overlayState == null) return;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _CategoryMenuOverlay(
        layerLink: _layerLink,
        dialogContext: context,
        appState: widget.appState,
        transaction: widget.transaction,
        onClose: _removeOverlay,
      ),
    );
    overlayState.insert(_overlayEntry!);
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openOverlay,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF0EDE8),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.displayCategory,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: chip,
    );
  }
}

class _CategoryMenuOverlay extends StatefulWidget {
  const _CategoryMenuOverlay({
    required this.layerLink,
    required this.dialogContext,
    required this.appState,
    required this.transaction,
    required this.onClose,
  });

  final LayerLink layerLink;
  /// Context for dialogs after the overlay is removed (e.g. parent [TransactionCategoryField]).
  final BuildContext dialogContext;
  final AppState appState;
  final Transaction transaction;
  final VoidCallback onClose;

  @override
  State<_CategoryMenuOverlay> createState() => _CategoryMenuOverlayState();
}

class _CategoryMenuOverlayState extends State<_CategoryMenuOverlay> {
  late final TextEditingController _newController;
  TextEditingController? _renameController;
  final FocusNode _renameFocusNode = FocusNode();
  String? _editingCanonical;

  @override
  void initState() {
    super.initState();
    _newController = TextEditingController();
  }

  @override
  void dispose() {
    _renameController?.dispose();
    _renameFocusNode.dispose();
    _newController.dispose();
    super.dispose();
  }

  void _commitPendingEditIfAny() {
    final prev = _editingCanonical;
    final c = _renameController;
    if (prev == null || c == null) return;
    final t = c.text.trim();
    if (t.isNotEmpty) {
      widget.appState.renameCategory(prev, t);
    }
    c.dispose();
    _renameController = null;
    _editingCanonical = null;
  }

  void _onNameZoneTap(String canonical, String label) {
    if (_editingCanonical == canonical) {
      _renameFocusNode.requestFocus();
      return;
    }
    setState(() {
      if (_editingCanonical != null) {
        final prev = _editingCanonical!;
        final ctrl = _renameController;
        if (ctrl != null) {
          final t = ctrl.text.trim();
          if (t.isNotEmpty) {
            widget.appState.renameCategory(prev, t);
          }
          ctrl.dispose();
          _renameController = null;
        }
        _editingCanonical = null;
      }
      _editingCanonical = canonical;
      _renameController = TextEditingController(text: label);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _renameFocusNode.requestFocus();
    });
  }

  void _finishRenameField(String canonical) {
    if (_editingCanonical != canonical || _renameController == null) return;
    final t = _renameController!.text.trim();
    if (t.isNotEmpty) {
      widget.appState.renameCategory(canonical, t);
    }
    setState(() {
      _renameController?.dispose();
      _renameController = null;
      _editingCanonical = null;
    });
  }

  void _selectCategoryAndClose(String canonical) {
    _commitPendingEditIfAny();
    widget.appState.setCategoryOverride(widget.transaction, canonical);
    final dc = widget.dialogContext;
    final t = widget.transaction;
    final app = widget.appState;
    widget.onClose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showSaveCategoryRuleDialogIfOutflow(
        context: dc,
        appState: app,
        transaction: t,
        categoryCanonical: canonical,
      );
    });
  }

  void _submitNew() {
    final raw = _newController.text;
    if (raw.trim().isEmpty) return;
    final name = raw.trim();
    widget.appState.createCategoryAndAssign(widget.transaction, raw);
    _newController.clear();
    final dc = widget.dialogContext;
    final t = widget.transaction;
    final app = widget.appState;
    widget.onClose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showSaveCategoryRuleDialogIfOutflow(
        context: dc,
        appState: app,
        transaction: t,
        categoryCanonical: name,
      );
    });
  }

  void _confirmDelete(BuildContext context, String canonical) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$canonical"?'),
        content: const Text(
          'Remove this category and clear it from assigned transactions?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_editingCanonical == canonical) {
                _renameController?.dispose();
                _renameController = null;
                _editingCanonical = null;
              }
              widget.appState.deleteCategory(canonical);
              widget.onClose();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Two zones: [name] = edit (InkWell), [rest] = select (InkWell), [trailing] = delete.
  Widget _categoryRow({
    required ThemeData theme,
    required ColorScheme cs,
    required String canonical,
    required String label,
  }) {
    final editing = _editingCanonical == canonical;

    return Material(
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Zone 1 — tap = rename (inline field when editing); generous padding for touch.
          InkWell(
            onTap: () => _onNameZoneTap(canonical, label),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 88,
                  minHeight: 44,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: editing && _renameController != null
                      ? SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _renameController,
                            focusNode: _renameFocusNode,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF0EDE8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) =>
                                _finishRenameField(canonical),
                            onTapOutside: (_) =>
                                _finishRenameField(canonical),
                          ),
                        )
                      : Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // Zone 2 — empty strip to the right of the name: tap = select + close.
          Expanded(
            child: InkWell(
              onTap: () => _selectCategoryAndClose(canonical),
              child: const SizedBox(
                height: 48,
                child: ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.remove_circle_outline_rounded,
              size: 20,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
            onPressed: () => _confirmDelete(context, canonical),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final width = (MediaQuery.sizeOf(context).width - 48).clamp(200.0, 320.0);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _commitPendingEditIfAny();
              widget.onClose();
            },
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 6),
          child: Material(
            elevation: 6,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            color: cs.surface,
            child: Container(
              width: width,
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE4E0D8)),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListenableBuilder(
                        listenable: widget.appState,
                        builder: (context, _) {
                          final names = categoryPickerCanonicals(
                            customCategories: widget.appState.customCategories,
                            hiddenLower: widget.appState.categoriesHiddenFromPicker,
                          );
                          if (names.isEmpty) {
                            return Center(
                              child: Text(
                                'No categories',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.45),
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: names.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              thickness: 1,
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                            ),
                            itemBuilder: (context, i) {
                              final canonical = names[i];
                              final label = applyCategoryDisplayRenames(
                                canonical,
                                widget.appState.categoryDisplayRenames,
                              );
                              return _categoryRow(
                                theme: theme,
                                cs: cs,
                                canonical: canonical,
                                label: label,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newController,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submitNew(),
                              decoration: InputDecoration(
                                hintText: 'New category',
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xFFF0EDE8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add and assign',
                            onPressed: _submitNew,
                            icon: Icon(
                              Icons.add_rounded,
                              color: cs.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
