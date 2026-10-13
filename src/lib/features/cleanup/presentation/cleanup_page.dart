import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as msicons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/card_highlight.dart';
import '../../../extensions.dart';
import '../../../i18n/generated/strings.g.dart';
import '../../../utils.dart';
import '../../../utils_gui.dart';
import '../data/cleanup_backup.dart';
import '../domain/entities/orphan_item.dart';
import 'cleanup_providers.dart';

/// Finds and removes leftovers of programs that are no longer installed.
class const CleanupPage({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupPageState() extends ConsumerState<CleanupPage> {
  bool _busy = false;
  CleanupOutcome? _outcome;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CleanupReport>>(cleanupScanProvider, (previous, next) {
      final CleanupReport? report = next.value;
      if (report != null) {
        ref.read(cleanupSelectionProvider.notifier).reset(report.items);
      }
    });

    final AsyncValue<CleanupReport> report = ref.watch(cleanupScanProvider);
    final Set<String> selection = ref.watch(cleanupSelectionProvider);

    final Object? scanError = report.whenOrNull(
      error: (Object error, StackTrace stackTrace) => error,
    );

    return ScaffoldPage.scrollable(
      padding: kScaffoldPagePadding,
      children: <Widget>[
        _summaryCard(report, selection),
        if (scanError != null)
          InfoBar(
            severity: InfoBarSeverity.error,
            title: Text(t.cleanupScanError),
            content: Text(scanError.toString()),
          ),
        if (_outcome != null) _outcomeCard(_outcome!),
        ..._groupCards(report.value, selection),
      ].withSpacing(5),
    );
  }

  Widget _summaryCard(AsyncValue<CleanupReport> report, Set<String> selection) {
    final String summary = report.when(
      loading: () => t.cleanupDescription,
      error: (Object error, StackTrace stackTrace) => t.cleanupDescription,
      data: (CleanupReport data) => data.total == 0
          ? t.cleanupNothingFound
          : '${data.total} ${t.cleanupFound} - ${selection.length} ${t.cleanupSelected}',
    );

    return CardHighlight(
      icon: msicons.FluentIcons.broom_20_regular,
      label: t.pageCleanup,
      description: summary,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Button(
            onPressed: report.isLoading || _busy ? null : () => ref.invalidate(cleanupScanProvider),
            child: Text(t.cleanupRescan),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: report.isLoading || _busy || selection.isEmpty
                ? null
                : () => _clean(report.requireValue, selection),
            child: Text(_busy ? t.cleanupCleaning : t.cleanupRemove),
          ),
        ],
      ),
    );
  }

  Future<void> _clean(CleanupReport report, Set<String> selection) async {
    final List<OrphanItem> items = report.items
        .where((OrphanItem item) => selection.contains(item.id))
        .toList(growable: false);
    if (items.isEmpty) return;
    setState(() => _busy = true);
    try {
      final CleanupOutcome outcome = await ref
          .read(cleanupRepositoryProvider)
          .clean(items, CleanupBackup.create());
      if (!mounted) return;
      setState(() => _outcome = outcome);
      ref.read(cleanupSelectionProvider.notifier).clear();
      ref.invalidate(cleanupScanProvider);
    } catch (error) {
      logger.e('cleanup: clean failed', error: error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _groupCards(CleanupReport? report, Set<String> selection) {
    if (report == null) return const [];
    final List<Widget> cards = [];
    for (final OrphanKind kind in OrphanKind.values) {
      final List<OrphanItem> items = report.ofKind(kind);
      if (items.isEmpty) continue;
      cards.add(
        CardHighlight(
          icon: _kindIcon(kind),
          label: _kindLabel(kind),
          description: '${items.length} ${t.cleanupItems}',
          children: <Widget>[for (final OrphanItem item in items) _row(item, selection)],
        ),
      );
    }
    return cards;
  }

  Widget _row(OrphanItem item, Set<String> selection) {
    return CardListTile(
      title: item.title,
      description: item.detail,
      extraTrailingPadding: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (item.confidence != OrphanConfidence.high)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: t.cleanupLowConfidence,
                child: Icon(msicons.FluentIcons.warning_20_regular, color: Colors.orange),
              ),
            ),
          Checkbox(
            checked: selection.contains(item.id),
            onChanged: (bool? value) => ref.read(cleanupSelectionProvider.notifier).toggle(item.id),
          ),
        ],
      ),
    );
  }

  Widget _outcomeCard(CleanupOutcome outcome) {
    final List<OrphanActionResult> failed = outcome.results
        .where((OrphanActionResult result) => !result.ok)
        .toList(growable: false);
    return CardHighlight(
      icon: msicons.FluentIcons.checkmark_circle_20_regular,
      label: t.cleanupResult,
      description: '${outcome.removed} ${t.cleanupRemoved} - ${outcome.failed} ${t.cleanupFailed}',
      action: FilledButton(
        onPressed: _busy ? null : () => _restore(outcome.backupPath),
        child: Text(t.cleanupRestore),
      ),
      children: <Widget>[
        CardListTile(
          title: t.cleanupBackup,
          description: outcome.backupPath,
          extraTrailingPadding: false,
        ),
        for (final OrphanActionResult result in failed)
          CardListTile(
            title: result.item.title,
            description: result.message,
            extraTrailingPadding: false,
          ),
      ],
    );
  }

  Future<void> _restore(String backupPath) async {
    setState(() => _busy = true);
    try {
      final int restored = await ref.read(cleanupRepositoryProvider).restore(backupPath);
      if (!mounted) return;
      setState(() => _outcome = null);
      ref.invalidate(cleanupScanProvider);
      logger.i('cleanup: restored $restored actions from $backupPath');
    } catch (error) {
      logger.e('cleanup: restore failed', error: error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _kindIcon(OrphanKind kind) => switch (kind) {
    OrphanKind.uninstallEntry => msicons.FluentIcons.apps_list_20_regular,
    OrphanKind.fileAssociation => msicons.FluentIcons.document_20_regular,
    OrphanKind.registry => msicons.FluentIcons.database_20_regular,
    OrphanKind.folder => msicons.FluentIcons.folder_20_regular,
    OrphanKind.scheduledTask => msicons.FluentIcons.clock_20_regular,
    OrphanKind.service => msicons.FluentIcons.settings_20_regular,
    OrphanKind.startupEntry => msicons.FluentIcons.rocket_20_regular,
  };

  String _kindLabel(OrphanKind kind) => switch (kind) {
    OrphanKind.uninstallEntry => t.cleanupUninstallEntry,
    OrphanKind.fileAssociation => t.cleanupFileAssociation,
    OrphanKind.registry => t.cleanupRegistry,
    OrphanKind.folder => t.cleanupFolder,
    OrphanKind.scheduledTask => t.cleanupScheduledTask,
    OrphanKind.service => t.cleanupService,
    OrphanKind.startupEntry => t.cleanupStartupEntry,
  };
}
