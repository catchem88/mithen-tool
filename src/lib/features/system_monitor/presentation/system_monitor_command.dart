import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:riverpod/riverpod.dart';

import '../../appx/presentation/appx_providers.dart';
import '../data/system_monitor_repository.dart';
import '../domain/entities/monitor_item.dart';

/// Command to scan (and optionally restore) the monitored system state.
final class SystemMonitorCommand({required final ProviderContainer container})
    extends Command<void> {
  this {
    argParser
      ..addFlag('scan', defaultsTo: true, help: 'Scans the system and prints the report')
      ..addFlag('fix', help: 'Restores every drifted item that can be fixed automatically');
  }

  @override
  String get name => 'monitor';

  @override
  String get description => '[System Monitor] Check disabled/removed items and fix drift';

  @override
  FutureOr<void> run() async {
    const repository = SystemMonitorRepository();
    final MonitorReport report = await repository.scan();

    for (final MonitorResult result in report.results) {
      final state = result.ok ? 'ok' : 'drifted';
      final String detail = result.actual ?? result.error ?? '';
      stdout.writeln(
        '${state.padRight(8)} ${result.item.kind.name.padRight(9)} ${result.item.title}  $detail',
      );
    }
    stdout.writeln('${report.okCount}/${report.total} checks in the expected state');

    if (argResults?.flag('fix') ?? false) {
      final List<MonitorResult> drifted = report.results
          .where((MonitorResult result) => !result.ok && result.item.autoFix)
          .toList(growable: false);
      for (final result in drifted) {
        stdout.writeln('Fixing ${result.item.title}...');
        await repository.fix(result.item, appxService: container.read(appxServiceProvider));
      }
    }

    exit(report.allOk ? 0 : 1);
  }
}
