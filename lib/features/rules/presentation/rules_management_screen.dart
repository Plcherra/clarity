import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../category_description_normalize.dart';
import '../../../category_rule.dart';
import '../../transactions/domain/spend_categories.dart';
import '../../transactions/widgets/transaction_category_dropdown.dart';

/// Lists saved description → category rules; search, tap row to edit in a sheet.
class RulesManagementScreen extends StatefulWidget {
  const RulesManagementScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<RulesManagementScreen> createState() => _RulesManagementScreenState();
}

class _RulesManagementScreenState extends State<RulesManagementScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CategoryRule> _filtered(List<CategoryRule> rules) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return List<CategoryRule>.from(rules);
    final app = widget.appState;
    return rules.where((r) {
      if (r.pattern.toLowerCase().contains(q)) return true;
      if (r.categoryCanonical.toLowerCase().contains(q)) return true;
      final display = applyCategoryDisplayRenames(
        r.categoryCanonical,
        app.categoryDisplayRenames,
      );
      if (display.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  String _ruleSourceCaption(CategoryRuleSource source) {
    switch (source) {
      case CategoryRuleSource.learnedFromTransaction:
        return 'From transaction';
      case CategoryRuleSource.manualFromRules:
        return 'Edited in Rules';
      case CategoryRuleSource.unknown:
        return 'Saved earlier';
    }
  }

  Future<void> _openRuleEditor(CategoryRule? rule) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: _RuleEditorSheet(
            rule: rule,
            appState: widget.appState,
            hostContext: context,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final rules = widget.appState.categoryRules;
        final filtered = _filtered(rules);

        return Scaffold(
          backgroundColor: const Color(0xFFF7F5F2),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text('Auto-categorization rules'),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Rules run before keyword suggestions. They do not delete your '
                    'transaction data.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.5),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${rules.length} rule${rules.length == 1 ? '' : 's'} saved',
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 0.6,
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openRuleEditor(null),
                        icon: Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: cs.primary,
                        ),
                        label: Text(
                          'New Rule',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by pattern or category',
                      filled: true,
                      fillColor: cs.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE4E0D8)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE4E0D8)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: cs.primary.withValues(alpha: 0.65),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: cs.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: rules.isEmpty
                        ? Center(
                            child: Text(
                              'No rules saved yet.\n'
                              'Assign a category to an outflow and save a pattern when prompted.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.45),
                                height: 1.4,
                              ),
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No rules match your search.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.45),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                itemBuilder: (context, i) {
                                  final rule = filtered[i];
                                  final displayCat = applyCategoryDisplayRenames(
                                    rule.categoryCanonical,
                                    widget.appState.categoryDisplayRenames,
                                  );
                                  final sourceCaption =
                                      _ruleSourceCaption(rule.source);
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _openRuleEditor(rule),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              rule.pattern,
                                              style: theme.textTheme.bodyLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.3,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.arrow_forward_rounded,
                                                  size: 16,
                                                  color: cs.onSurface.withValues(
                                                    alpha: 0.35,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    displayCat,
                                                    style: theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: cs.onSurface
                                                              .withValues(
                                                                alpha: 0.72,
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              sourceCaption,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        cs.onSurface.withValues(
                                                      alpha: 0.38,
                                                    ),
                                                    letterSpacing: 0.2,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RuleEditorSheet extends StatefulWidget {
  const _RuleEditorSheet({
    this.rule,
    required this.appState,
    required this.hostContext,
  });

  /// Null = create a new rule (same sheet UI, empty pattern).
  final CategoryRule? rule;
  final AppState appState;
  final BuildContext hostContext;

  @override
  State<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<_RuleEditorSheet> {
  late final TextEditingController _patternController;
  late String _categoryCanonical;

  @override
  void initState() {
    super.initState();
    final existing = widget.rule;
    if (existing != null) {
      _patternController = TextEditingController(text: existing.pattern);
      _categoryCanonical = existing.categoryCanonical;
    } else {
      _patternController = TextEditingController();
      final names = categoryPickerCanonicals(
        customCategories: widget.appState.customCategories,
        hiddenLower: widget.appState.categoriesHiddenFromPicker,
      );
      _categoryCanonical =
          names.isNotEmpty ? names.first : kSelectableSpendCategories.first;
    }
  }

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  String get _categoryDisplayLabel {
    return applyCategoryDisplayRenames(
      _categoryCanonical,
      widget.appState.categoryDisplayRenames,
    );
  }

  Future<void> _pickCategory() async {
    final names = categoryPickerCanonicals(
      customCategories: widget.appState.customCategories,
      hiddenLower: widget.appState.categoriesHiddenFromPicker,
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        return SizedBox(
          height: maxH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  'Category',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: names.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                  itemBuilder: (_, i) {
                    final canonical = names[i];
                    final label = applyCategoryDisplayRenames(
                      canonical,
                      widget.appState.categoryDisplayRenames,
                    );
                    final selected = canonical == _categoryCanonical;
                    return ListTile(
                      title: Text(label),
                      selected: selected,
                      onTap: () => Navigator.pop(ctx, canonical),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _categoryCanonical = picked);
    }
  }

  Future<void> _deleteRule() async {
    final rule = widget.rule;
    if (rule == null) return;
    final displayCat = applyCategoryDisplayRenames(
      rule.categoryCanonical,
      widget.appState.categoryDisplayRenames,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete rule?'),
        content: Text(
          'Remove matching "${rule.pattern}" → "$displayCat"? '
          'Future imports will no longer use this rule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final removed = await widget.appState.deleteCategoryRule(rule.id);
    if (!mounted) return;
    if (!removed) {
      if (!widget.hostContext.mounted) return;
      ScaffoldMessenger.of(widget.hostContext).showSnackBar(
        const SnackBar(content: Text('Could not delete rule.')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final raw = _patternController.text;
    final normalized = normalizeDescriptionForMatching(raw);
    if (normalized.length < kMinCategoryRulePatternLength) {
      if (!widget.hostContext.mounted) return;
      ScaffoldMessenger.of(widget.hostContext).showSnackBar(
        SnackBar(
          content: Text(
            'Pattern must be at least $kMinCategoryRulePatternLength characters.',
          ),
        ),
      );
      return;
    }

    final existing = widget.rule;
    final bool ok;
    if (existing != null) {
      ok = await widget.appState.updateCategoryRuleById(
        id: existing.id,
        patternRaw: raw,
        categoryCanonical: _categoryCanonical,
      );
    } else {
      ok = await widget.appState.addOrUpdateCategoryRuleByPattern(
        raw,
        _categoryCanonical,
        sourceForNewRule: CategoryRuleSource.manualFromRules,
      );
    }

    if (!mounted) return;
    if (!ok) {
      if (!widget.hostContext.mounted) return;
      ScaffoldMessenger.of(widget.hostContext).showSnackBar(
        SnackBar(
          content: Text(
            existing != null
                ? 'Could not save. Another rule may already use this pattern.'
                : 'Could not save rule. Check the pattern and try again.',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.rule == null ? 'New rule' : 'Edit rule',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.rule == null
                ? 'Add a text match and category. Rules apply to future imports.'
                : 'Change the match text or category. Rules apply to future imports.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.5),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Pattern',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _patternController,
            decoration: InputDecoration(
              hintText: 'Text the description should contain',
              filled: true,
              fillColor: const Color(0xFFF0EDE8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
          ),
          const SizedBox(height: 20),
          Text(
            'Category',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _pickCategory,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: Color(0xFFE4E0D8)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _categoryDisplayLabel,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
          if (widget.rule != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _deleteRule,
              style: TextButton.styleFrom(
                foregroundColor: cs.error,
              ),
              child: const Text('Delete rule…'),
            ),
          ],
        ],
      ),
    );
  }
}

