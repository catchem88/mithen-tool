import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as msicons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/card_highlight.dart';
import '../../../core/widgets/loading_dialog.dart';
import '../../../extensions.dart';
import '../../../i18n/generated/strings.g.dart';
import '../../../utils.dart';
import '../../../utils_gui.dart';
import '../../appx/presentation/appx_providers.dart';
import '../domain/entities/monitor_item.dart';
import 'system_monitor_providers.dart';

/// Whether the automatic scan of this app session already ran.
bool _autoScanPerformed = false;

/// Shows whether the disabled/removed items are still in the expected state.
class const SystemMonitorPage({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SystemMonitorPage> createState() => _SystemMonitorPageState();
}

class _SystemMonitorPageState() extends ConsumerState<SystemMonitorPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!_autoScanPerformed) {
      _autoScanPerformed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  /// Runs [work] behind a modal spinner that blocks the whole UI.
  Future<T> _withLoading<T>(String title, String message, Future<T> Function() work) async {
    setState(() => _busy = true);
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final Future<Object?> dialog = showLoadingDialog(context, title, message: message);
    try {
      return await work();
    } finally {
      if (navigator.canPop()) navigator.pop();
      await dialog;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    await _withLoading(t.systemMonitorRescan, t.systemMonitorScanning, () async {
      try {
        ref.invalidate(systemMonitorReportProvider);
        await ref.read(systemMonitorReportProvider.future);
      } catch (error) {
        logger.e('system_monitor: scan failed', error: error);
      }
    });
  }

  Future<void> _fix(MonitorResult result) async {
    await _withLoading(t.systemMonitorFix, t.systemMonitorFixing, () async {
      try {
        await ref
            .read(systemMonitorRepositoryProvider)
            .fix(result.item, appxService: ref.read(appxServiceProvider));
        ref.invalidate(systemMonitorReportProvider);
        await ref.read(systemMonitorReportProvider.future);
      } catch (error) {
        logger.e('system_monitor: fix failed for ${result.item.name}', error: error);
      }
    });
  }

  /// Fixes every drifted item that can be fixed automatically, one by one.
  Future<void> _fixAll(MonitorReport report) async {
    await _withLoading(t.systemMonitorFixAll, t.systemMonitorFixing, () async {
      final List<MonitorResult> drifted = report.results
          .where((MonitorResult result) => !result.ok && result.item.autoFix)
          .toList(growable: false);
      for (final result in drifted) {
        try {
          await ref
              .read(systemMonitorRepositoryProvider)
              .fix(result.item, appxService: ref.read(appxServiceProvider));
        } catch (error) {
          logger.e('system_monitor: fix all failed for ${result.item.name}', error: error);
        }
      }
      ref.invalidate(systemMonitorReportProvider);
      await ref.read(systemMonitorReportProvider.future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MonitorReport> report = ref.watch(systemMonitorReportProvider);
    final int fixable =
        report.value?.results
            .where((MonitorResult result) => !result.ok && result.item.autoFix)
            .length ??
        0;

    return ScaffoldPage.scrollable(
      padding: kScaffoldPagePadding,
      children: [_summaryCard(report, fixable), ..._groupCards(report.value)].withSpacing(5),
    );
  }

  Widget _summaryCard(AsyncValue<MonitorReport> report, int fixable) {
    final String summary = report.when(
      loading: () => t.systemMonitorScanning,
      error: (Object error, StackTrace stackTrace) => error.toString(),
      data: (MonitorReport data) =>
          data.allOk ? t.systemMonitorSummaryOk : t.systemMonitorSummaryDrifted,
    );

    return CardHighlight(
      icon: msicons.FluentIcons.shield_20_regular,
      label: t.pageSystemMonitor,
      description: '$summary - ${t.systemMonitorDescription}',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Button(
            onPressed: _busy || report.isLoading ? null : _scan,
            child: Text(t.systemMonitorRescan),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy || report.isLoading || fixable == 0
                ? null
                : () => _fixAll(report.requireValue),
            child: Text(t.systemMonitorFixAll),
          ),
        ],
      ),
    );
  }

  List<Widget> _groupCards(MonitorReport? report) {
    if (report == null) return const [];

    final List<Widget> cards = [];
    for (final MonitorCheckKind kind in MonitorCheckKind.values) {
      final List<MonitorResult> results = report.results
          .where((MonitorResult result) => result.item.kind == kind)
          .toList(growable: false);
      if (results.isEmpty) continue;

      final int ok = results.where((MonitorResult result) => result.ok).length;
      cards.add(
        CardHighlight(
          icon: _kindIcon(kind),
          label: _kindLabel(kind),
          description: '$ok/${results.length}',
          children: [for (final MonitorResult result in results) _row(result)],
        ),
      );
    }
    return cards;
  }

  Widget _row(MonitorResult result) {
    final String detail = <String>[
      ?result.item.description,
      ?(result.ok ? null : (result.error ?? result.actual ?? '')),
    ].join(' - ');
    return CardListTile(
      title: result.item.title,
      description: detail.isEmpty ? null : detail,
      trailing: result.ok
          ? Icon(msicons.FluentIcons.checkmark_circle_20_regular, color: Colors.green)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(msicons.FluentIcons.warning_20_regular, color: Colors.red),
                const SizedBox(width: 8),
                if (result.item.autoFix)
                  Button(
                    onPressed: _busy ? null : () => _fix(result),
                    child: Text(t.systemMonitorFix),
                  ),
              ],
            ),
    );
  }

  IconData _kindIcon(MonitorCheckKind kind) => switch (kind) {
    MonitorCheckKind.appx => msicons.FluentIcons.apps_20_regular,
    MonitorCheckKind.service => msicons.FluentIcons.settings_20_regular,
    MonitorCheckKind.feature => msicons.FluentIcons.window_20_regular,
    MonitorCheckKind.task => msicons.FluentIcons.clock_20_regular,
    MonitorCheckKind.registry => msicons.FluentIcons.database_20_regular,
    MonitorCheckKind.hosts => msicons.FluentIcons.globe_20_regular,
  };

  String _kindLabel(MonitorCheckKind kind) => switch (kind) {
    MonitorCheckKind.appx => t.systemMonitorKindAppx,
    MonitorCheckKind.service => t.systemMonitorKindService,
    MonitorCheckKind.feature => t.systemMonitorKindFeature,
    MonitorCheckKind.task => t.systemMonitorKindTask,
    MonitorCheckKind.registry => t.systemMonitorKindRegistry,
    MonitorCheckKind.hosts => t.systemMonitorKindHosts,
  };
}
