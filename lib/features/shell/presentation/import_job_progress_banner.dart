import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/ui_dependencies.dart';

/// Top banner for the unified CSV upload + AI categorization job.
class ImportJobProgressBanner extends StatelessWidget {
  const ImportJobProgressBanner({super.key, required this.controller});

  final ImportJobStatusController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = controller.importProgressTotal;
    final done = controller.importProgressCompleted;
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
class ImportJobStatusHost extends StatefulWidget {
  const ImportJobStatusHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final ImportJobStatusController controller;
  final Widget child;

  @override
  State<ImportJobStatusHost> createState() => _ImportJobStatusHostState();
}

class _ImportJobStatusHostState extends State<ImportJobStatusHost> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final msg = widget.controller.consumeImportSnackMessage();
          if (msg != null && msg.isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.controller.importRunning)
              ImportJobProgressBanner(controller: widget.controller),
            if (!widget.controller.importRunning &&
                widget.controller.persistentImportMessage != null)
              _PersistentImportMessageBanner(controller: widget.controller),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

class _PersistentImportMessageBanner extends StatelessWidget {
  const _PersistentImportMessageBanner({required this.controller});

  final ImportJobStatusController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isError = controller.persistentImportMessageIsError;
    final background = isError
        ? cs.errorContainer
        : cs.tertiaryContainer.withValues(alpha: 0.9);
    final foreground = isError ? cs.onErrorContainer : cs.onTertiaryContainer;
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              color: foreground,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                controller.persistentImportMessage ?? '',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: controller.dismissPersistentImportMessage,
              icon: Icon(Icons.close_rounded, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
