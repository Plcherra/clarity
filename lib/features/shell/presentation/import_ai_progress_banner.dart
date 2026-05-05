import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/ui_dependencies.dart';

/// Top banner for the unified CSV upload + AI categorization job.
class ImportAiProgressBanner extends StatelessWidget {
  const ImportAiProgressBanner({super.key, required this.controller});

  final ImportAiStatusController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = controller.importAiProgressTotal;
    final done = controller.importAiProgressCompleted;
    final pct = total > 0 ? ((done / total) * 100).round() : 0;
    final message = controller.importProgressMessage;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$message $pct%',
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

/// Banner while running, optional snack from import AI status state.
class ImportAiStatusHost extends StatefulWidget {
  const ImportAiStatusHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final ImportAiStatusController controller;
  final Widget child;

  @override
  State<ImportAiStatusHost> createState() => _ImportAiStatusHostState();
}

class _ImportAiStatusHostState extends State<ImportAiStatusHost> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final msg = widget.controller.consumeImportAiSnackMessage();
          if (msg != null && msg.isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.controller.importAiCategorizationRunning)
              ImportAiProgressBanner(controller: widget.controller),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}
