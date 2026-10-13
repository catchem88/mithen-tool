import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils.dart';

/// Undo log for a cleanup run: registry exports, task XML and quarantine folders.
final class CleanupBackup._(final Directory directory, final Directory quarantine) {
  final List<Map<String, Object?>> _actions = [];

  static Directory get baseDirectory => Directory(
    p.join(
      Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
      'Mithen-Tool',
      'cleanup',
    ),
  );

  /// Creates a new timestamped backup folder with its quarantine subfolder.
  static CleanupBackup create() {
    final String stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final directory = Directory(p.join(baseDirectory.path, stamp))..createSync(recursive: true);
    final quarantine = Directory(p.join(directory.path, 'quarantine'))..createSync(recursive: true);
    return CleanupBackup._(directory, quarantine);
  }

  /// Records one action in the undo manifest.
  void record(String kind, String target, [Map<String, Object?> extra = const {}]) {
    _actions.add(<String, Object?>{'kind': kind, 'target': target, ...extra});
  }

  /// File that holds the `reg export` of one registry key.
  String registryBackupFile(String hive, String path) {
    final String safe = path.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    return p.join(directory.path, '$hive-$safe.reg');
  }

  /// File that holds the XML of one scheduled task.
  String taskBackupFile(String taskPath, String taskName) {
    final String safe = (taskPath + taskName).replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    return p.join(directory.path, 'task-$safe.xml');
  }

  /// Exports a registry key with `reg export` so it can be re-imported.
  ///
  /// Returns the backup file, or null when the export failed.
  Future<String?> exportRegistryKey(String hive, String path) async {
    final String file = registryBackupFile(hive, path);
    try {
      final ProcessResult result = await Process.run('reg.exe', <String>[
        'export',
        '$hive\\$path',
        file,
        '/y',
      ]);
      return result.exitCode == 0 ? file : null;
    } catch (error) {
      logger.w('cleanup: reg export failed for $hive\\$path', error: error);
      return null;
    }
  }

  /// Saves a scheduled task definition as XML so it can be re-registered.
  ///
  /// Returns the backup file, or null when the export failed.
  Future<String?> saveTaskXml(String taskPath, String taskName) async {
    final String file = taskBackupFile(taskPath, taskName);
    try {
      final ProcessResult result = await Process.run('schtasks', <String>[
        '/query',
        '/xml',
        '$taskPath$taskName',
      ]);
      if (result.exitCode != 0) return null;
      await File(file).writeAsString(result.stdout.toString());
      return file;
    } catch (error) {
      logger.w('cleanup: task export failed for $taskPath$taskName', error: error);
      return null;
    }
  }

  /// Moves a folder into the quarantine so it can be restored.
  Future<String?> quarantineFolder(String sourcePath) async {
    try {
      final source = Directory(sourcePath);
      if (!source.existsSync()) return null;
      final String name = p.basename(sourcePath);
      String target = p.join(quarantine.path, name);
      var index = 1;
      while (Directory(target).existsSync()) {
        target = p.join(quarantine.path, '$name ($index)');
        index++;
      }
      try {
        source.renameSync(target);
      } catch (_) {
        _copyDirectory(source, Directory(target));
        source.deleteSync(recursive: true);
      }
      return target;
    } catch (error) {
      logger.w('cleanup: could not quarantine $sourcePath', error: error);
      return null;
    }
  }

  /// Writes the undo manifest.
  Future<void> save() async {
    final file = File(p.join(directory.path, 'manifest.json'));
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'createdAt': DateTime.now().toIso8601String(),
        'actions': _actions,
      }),
    );
  }

  void _copyDirectory(Directory source, Directory target) {
    target.createSync(recursive: true);
    for (final FileSystemEntity entity in source.listSync(recursive: true, followLinks: false)) {
      final String relative = p.relative(entity.path, from: source.path);
      final String destination = p.join(target.path, relative);
      if (entity is Directory) {
        Directory(destination).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(destination)).createSync(recursive: true);
        entity.copySync(destination);
      }
    }
  }
}
