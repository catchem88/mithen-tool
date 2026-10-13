import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/cleanup_backup.dart';
import '../data/cleanup_repository.dart';
import '../domain/entities/orphan_item.dart';

/// Command to scan for and remove leftovers of uninstalled programs.
final class CleanupCommand() extends Command<void> {
  this {
    argParser
      ..addFlag('scan', defaultsTo: true, help: 'Scans the system and prints the leftovers')
      ..addFlag('apply', help: 'Removes the selected leftovers')
      ..addFlag('all', help: 'Also removes low confidence leftovers')
      ..addFlag('restore', help: 'Restores a previous cleanup run')
      ..addOption('backup', help: 'Backup folder to restore');
  }

  @override
  String get name => 'cleanup';

  @override
  String get description => '[Cleanup] Find and remove leftovers of uninstalled programs';
  @override
  FutureOr<void> run() async {
    const repository = CleanupRepository();

    if (argResults?.flag('restore') ?? false) {
      final String backupPath = (argResults?['backup'] as String?) ?? _latestBackup() ?? '';
      if (backupPath.isEmpty) {
        stdout.writeln('No cleanup backup found');
        return;
      }
      final int restored = await repository.restore(backupPath);
      stdout.writeln('Restored $restored actions from $backupPath');
      return;
    }

    final CleanupReport report = await repository.scan();
    for (final OrphanItem item in report.items) {
      stdout.writeln('${item.kind.name.padRight(15)} ${item.title}  ${item.detail}');
    }
    stdout.writeln('${report.total} leftovers found');
    if (!(argResults?.flag('apply') ?? false)) return;

    final bool all = argResults?.flag('all') ?? false;
    final List<OrphanItem> items = report.items
        .where((OrphanItem item) => all || item.selectedByDefault)
        .toList(growable: false);
    final CleanupOutcome outcome = await repository.clean(items, CleanupBackup.create());
    stdout.writeln('${outcome.removed} removed, ${outcome.failed} failed');
    stdout.writeln('Backup: ${outcome.backupPath}');
  }

  String? _latestBackup() {
    final Directory directory = CleanupBackup.baseDirectory;
    if (!directory.existsSync()) return null;
    final List<Directory> entries = directory.listSync().whereType<Directory>().toList()
      ..sort((Directory a, Directory b) => b.path.compareTo(a.path));
    return entries.isEmpty ? null : entries.first.path;
  }
}
