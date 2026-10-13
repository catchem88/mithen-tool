import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/generated/strings.g.dart';
import '../../../utils.dart';
import '../domain/entities/orphan_item.dart';
import 'cleanup_providers.dart';

/// Runs the cleanup scan behind a blocking dialog and offers to remove the findings.
///
/// Returns the report, or null when the dialog was closed or cancelled.
Future<CleanupReport?> showCleanupScanDialog(BuildContext context, WidgetRef ref) async {
  CleanupReport? report;
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => _ScanDialog(
      ref: ref,
      onDone: (CleanupReport? value) {
        report = value;
        Navigator.of(dialogContext).pop();
      },
    ),
  );
  return report;
}

final class const _ScanDialog({
  required final WidgetRef ref,
  required final void Function(CleanupReport?) onDone,
}) extends StatefulWidget {
  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState() extends State<_ScanDialog> {
  bool _scanning = true;
  bool _removing = false;
  bool _cancelRequested = false;
  Object? _error;
  String? _progress;
  Completer<bool>? _decision;
  CleanupReport? _report;
  CleanupRunResult? _run;
  Set<String> _selection = const <String>{};

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _report = null;
      _run = null;
    });
    try {
      final CleanupReport report = await widget.ref
          .read(cleanupRepositoryProvider)
          .scan(onError: _onScanError);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _report = report;
        _selection = <String>{
          for (final OrphanItem item in report.items)
            if (item.selectedByDefault) item.id,
        };
      });
    } on ScanCancelledException {
      widget.onDone(null);
    } catch (error) {
      logger.e('cleanup: scan failed', error: error);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = error;
      });
    }
  }

  /// Lets the user skip a failed scan step or cancel the whole scan.
  Future<bool> _onScanError(OrphanKind kind, Object error) async {
    final decision = Completer<bool>();
    if (!mounted) return true;
    setState(() {
      _error = error;
      _decision = decision;
    });
    final bool skip = await decision.future;
    if (!mounted) return skip;
    setState(() {
      _error = null;
      _decision = null;
    });
    return skip;
  }

  /// Removes the selected leftovers, then keeps scanning and removing until the
  /// system comes out clean (max 2 passes). Items the user unchecked are kept.
  Future<void> _removeSelected() async {
    final CleanupReport? report = _report;
    if (report == null) return;
    final excludedIds = <String>{
      for (final OrphanItem item in report.items)
        if (!_selection.contains(item.id)) item.id,
    };
    if (excludedIds.length == report.items.length) return;
    setState(() {
      _removing = true;
      _cancelRequested = false;
      _progress = null;
    });
    try {
      final CleanupRunResult run = await widget.ref
          .read(cleanupRepositoryProvider)
          .runPasses(
            initialReport: report,
            excludedIds: excludedIds,
            onError: _onScanError,
            onProgress: (String message) {
              if (mounted) setState(() => _progress = message);
            },
            isCancelled: () => _cancelRequested,
          );
      if (!mounted) return;
      setState(() {
        _run = run;
        _report = null;
        _selection = const <String>{};
      });
    } catch (error) {
      logger.e('cleanup: run failed', error: error);
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  void _close() => widget.onDone(null);

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
      title: Text(_title),
      content: _content(),
      actions: _actions(),
    );
  }

  String get _title => switch (_run) {
    CleanupRunResult() => t.cleanupResult,
    _ => _report != null ? t.cleanupFoundTitle : t.pageCleanup,
  };

  Widget? _content() {
    if (_scanning || _removing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: .center,
          children: [
            const ProgressRing(),
            const SizedBox(height: 12),
            Text(_removing ? t.cleanupRemoving : t.cleanupScanning),
            if (_removing && _progress != null) ...[
              const SizedBox(height: 8),
              Text(
                _progress!,
                style: const TextStyle(fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(t.cleanupScanError),
              const SizedBox(height: 6),
              Text(
                _error.toString(),
                style: const TextStyle(fontSize: 11),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }
    if (_run != null) {
      final List<OrphanActionResult> failed = _run!.passes
          .expand((CleanupPassResult pass) => pass.results)
          .where((OrphanActionResult result) => !result.ok)
          .toList(growable: false);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final CleanupPassResult pass in _run!.passes)
            Text(
              'Pass ${pass.pass}: ${pass.removed} ${t.cleanupRemoved} - ${pass.failed} ${t.cleanupFailed}',
            ),
          const SizedBox(height: 8),
          Text(
            _run!.remaining.isEmpty
                ? t.cleanupNothingFound
                : '${_run!.remaining.length} ${t.cleanupRemaining}',
          ),
          const SizedBox(height: 8),
          Text('${t.cleanupBackup}: ${_run!.backupPath}'),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ListView.builder(
                itemCount: failed.length,
                itemBuilder: (BuildContext context, int index) {
                  final OrphanActionResult result = failed[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${result.item.title}: ${result.message}',
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );
    }
    final CleanupReport? report = _report;
    if (report == null || report.items.isEmpty) {
      return Text(_error?.toString() ?? t.cleanupNothingFound);
    }
    return SizedBox(height: 340, child: _resultsList(report));
  }

  Widget _resultsList(CleanupReport report) {
    return ListView.builder(
      itemCount: report.items.length,
      itemBuilder: (BuildContext context, int index) {
        final OrphanItem item = report.items[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                checked: _selection.contains(item.id),
                onChanged: (bool? value) {
                  setState(() {
                    final selection = <String>{..._selection};
                    if (value ?? false) {
                      selection.add(item.id);
                    } else {
                      selection.remove(item.id);
                    }
                    _selection = selection;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title),
                    Text(
                      item.detail,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Null while working - an empty action list would render an empty footer bar.
  List<Widget>? _actions() {
    if (_decision != null) {
      return [
        Button(onPressed: () => _decision?.complete(false), child: Text(t.cleanupCancel)),
        FilledButton(onPressed: () => _decision?.complete(true), child: Text(t.cleanupSkip)),
      ];
    }
    if (_scanning) return null;
    if (_removing) {
      return [
        Button(
          onPressed: () => setState(() => _cancelRequested = true),
          child: Text(t.cleanupCancel),
        ),
      ];
    }
    if (_run != null || _error != null) {
      return [FilledButton(onPressed: _close, child: Text(t.close))];
    }
    return [
      Button(onPressed: _close, child: Text(t.close)),
      FilledButton(
        onPressed: _selection.isEmpty ? null : _removeSelected,
        child: Text(t.cleanupRemove),
      ),
    ];
  }
}
