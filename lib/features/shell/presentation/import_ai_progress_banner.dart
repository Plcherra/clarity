import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/app_state.dart';

/// Top banner: `Categorizing transactions… X of Y (Z%)`.
class ImportAiProgressBanner extends StatelessWidget {
  const ImportAiProgressBanner({
    super.key,
    required this.appState,
  });

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = appState.importAiProgressTotal;
    final done = appState.importAiProgressCompleted;
    final pct = total > 0 ? ((done / total) * 100).round() : 0;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Categorizing transactions… $done of $total ($pct%)',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? done / total : null,
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner while running, optional snack when [AppState.importAiSnackMessage] is set.
class ImportAiStatusHost extends StatefulWidget {
  const ImportAiStatusHost({
    super.key,
    required this.appState,
    required this.child,
  });

  final AppState appState;
  final Widget child;

  @override
  State<ImportAiStatusHost> createState() => _ImportAiStatusHostState();
}

class _ImportAiStatusHostState extends State<ImportAiStatusHost> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final msg = widget.appState.consumeImportAiSnackMessage();
          if (msg != null && msg.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.appState.importAiCategorizationRunning)
              ImportAiProgressBanner(appState: widget.appState),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}
