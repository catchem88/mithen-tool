import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

import '../../../core/services/win_registry_service.dart';
import '../../../utils.dart';
import '../../appx/domain/appx_service.dart';
import '../domain/entities/monitor_item.dart';
import 'system_monitor_manifest.dart';

/// Reads the current system state and compares it with [systemMonitorManifest].
final class const SystemMonitorRepository() {
  static const String _serviceKeyRoot = r'SYSTEM\ControlSet001\Services';

  /// Runs every check in the manifest and returns the aggregated report.
  Future<MonitorReport> scan() async {
    final Set<String> families = await _installedAppxFamilies();
    final Map<String, String> features = await _featureStates();
    final Map<String, String> tasks = await _taskStates();
    final String hosts = await _readHosts();

    final List<MonitorResult> results = [];
    for (final MonitorItem item in systemMonitorManifest) {
      results.add(_evaluate(item, families, features, tasks, hosts));
    }
    return MonitorReport(results: results, scannedAt: DateTime.now());
  }

  /// Restores [item] to its expected state.
  Future<void> fix(MonitorItem item, {required AppxService appxService}) async {
    switch (item.kind) {
      case MonitorCheckKind.appx:
        await appxService.removePackages(prefixes: {item.name}, allUsers: true);
      case MonitorCheckKind.service:
        await WinRegistryService.writeRegistryValue(
          LOCAL_MACHINE,
          '$_serviceKeyRoot\\${item.service}',
          'Start',
          item.expectedStart ?? 4,
          useTrustedInstaller: true,
        );
      case MonitorCheckKind.feature:
        final String state = await _featureState(item.name);
        if (state.isEmpty ||
            (item.expected == MonitorExpected.disabled && state == 'DisabledWithPayloadRemoved')) {
          // The feature is not part of this image - nothing to enable or disable.
          return;
        }
        final verb = item.expected == MonitorExpected.enabled ? 'Enable' : 'Disable';
        await _runPSStrict(
          '$verb-WindowsOptionalFeature -Online -FeatureName ${item.name} -NoRestart -ErrorAction Stop',
        );
      case MonitorCheckKind.task:
        final String taskPath = _normalizeTaskPath(item.taskPath);
        if (!await _taskExists(taskPath, item.name)) {
          // The task does not exist on this build - nothing to disable.
          return;
        }
        final verb = item.expected == MonitorExpected.disabled ? 'Disable' : 'Enable';
        await _runPSStrict(
          "$verb-ScheduledTask -TaskPath '$taskPath' -TaskName '${item.name}' -ErrorAction Stop",
        );
      case MonitorCheckKind.registry:
        final BaseRegistryKey hive = item.userHive ? CURRENT_USER : LOCAL_MACHINE;
        if (item.expected == MonitorExpected.valueAbsent) {
          await WinRegistryService.deleteValue(hive, item.registryPath!, item.registryValue!);
        } else if (item.registryType == 'dword') {
          await WinRegistryService.writeRegistryValue(
            hive,
            item.registryPath!,
            item.registryValue!,
            int.parse(item.expectedData!),
          );
        } else {
          await WinRegistryService.writeRegistryValue(
            hive,
            item.registryPath!,
            item.registryValue!,
            item.expectedData!,
          );
        }
      case MonitorCheckKind.hosts:
        break;
    }
  }

  MonitorResult _evaluate(
    MonitorItem item,
    Set<String> families,
    Map<String, String> features,
    Map<String, String> tasks,
    String hosts,
  ) {
    try {
      final String? actual = _actualState(item, families, features, tasks, hosts);
      return MonitorResult(item: item, ok: _isExpected(item, actual), actual: actual);
    } catch (error) {
      return MonitorResult(item: item, ok: false, error: error.toString());
    }
  }

  String? _actualState(
    MonitorItem item,
    Set<String> families,
    Map<String, String> features,
    Map<String, String> tasks,
    String hosts,
  ) {
    switch (item.kind) {
      case MonitorCheckKind.appx:
        final String needle = item.name.toLowerCase();
        final Iterable<String> matches = families.where((f) => f.toLowerCase().startsWith(needle));
        return matches.isEmpty ? null : matches.first;
      case MonitorCheckKind.service:
        return WinRegistryService.readInt(
          LOCAL_MACHINE,
          '$_serviceKeyRoot\\${item.service}',
          'Start',
        )?.toString();
      case MonitorCheckKind.feature:
        return features[item.name] ?? 'absent';
      case MonitorCheckKind.task:
        final String state = tasks[item.name] ?? '';
        return state.isEmpty ? 'absent' : state;
      case MonitorCheckKind.registry:
        return _readRegistry(item);
      case MonitorCheckKind.hosts:
        return hosts.contains(item.expectedData!) ? 'present' : 'missing';
    }
  }

  bool _isExpected(MonitorItem item, String? actual) {
    switch (item.expected) {
      case MonitorExpected.absent:
      case MonitorExpected.valueAbsent:
        return actual == null;
      case MonitorExpected.disabled:
        return actual == 'Disabled' ||
            actual == 'DisablePending' ||
            actual == 'DisabledWithPayloadRemoved' ||
            ((item.kind == MonitorCheckKind.feature || item.kind == MonitorCheckKind.task) &&
                actual == 'absent');
      case MonitorExpected.enabled:
        return actual == 'Enabled' || actual == 'EnablePending';
      case MonitorExpected.value:
        if (item.expectedStart != null) {
          return actual == item.expectedStart.toString();
        }
        return actual == item.expectedData;
      case MonitorExpected.hostsEntry:
        return actual == 'present';
    }
  }

  String? _readRegistry(MonitorItem item) {
    final BaseRegistryKey hive = item.userHive ? CURRENT_USER : LOCAL_MACHINE;
    if (item.registryType == 'dword') {
      return WinRegistryService.readInt(hive, item.registryPath!, item.registryValue!)?.toString();
    }
    return WinRegistryService.readString(hive, item.registryPath!, item.registryValue!);
  }

  Future<Set<String>> _installedAppxFamilies() async {
    final String output = await _runPS(
      r'(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue).PackageFamilyName',
    );
    return output
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
  }

  Future<Map<String, String>> _featureStates() async {
    final String names = systemMonitorManifest
        .where((item) => item.kind == MonitorCheckKind.feature)
        .map((item) => "'${item.name}'")
        .join(',');
    if (names.isEmpty) return {};
    final script =
        'Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | '
        'Where-Object { @($names) -contains \$_.FeatureName } | '
        r'ForEach-Object { "$($_.FeatureName)=$($_.State)" }';
    return _parsePairs(await _runPS(script));
  }

  Future<Map<String, String>> _taskStates() async {
    final List<MonitorItem> tasks = systemMonitorManifest
        .where((item) => item.kind == MonitorCheckKind.task)
        .toList();
    if (tasks.isEmpty) return {};
    final String pairs = tasks
        .map((item) => "@{p='${_normalizeTaskPath(item.taskPath)}';n='${item.name}'}")
        .join(',');
    final script =
        '@($pairs) | ForEach-Object { '
        r'$s=(Get-ScheduledTask -TaskPath $_.p -TaskName $_.n -ErrorAction SilentlyContinue).State; '
        r'"$($_.n)=$s" }';
    return _parsePairs(await _runPS(script));
  }

  Map<String, String> _parsePairs(String output) {
    final Map<String, String> map = {};
    for (final String line in output.split(RegExp(r'\r?\n'))) {
      final String trimmed = line.trim();
      final int separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      map[trimmed.substring(0, separator)] = trimmed.substring(separator + 1);
    }
    return map;
  }

  Future<String> _readHosts() async {
    final String root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    try {
      final file = File('$root\\System32\\drivers\\etc\\hosts');
      if (!file.existsSync()) return '';
      return await file.readAsString();
    } catch (error) {
      logger.w('system_monitor: failed to read the hosts file', error: error);
      return '';
    }
  }

  /// Formats a task folder path the way the ScheduledTasks cmdlets expect it.
  static String _normalizeTaskPath(String? path) {
    String normalized = (path ?? '').trim();
    if (!normalized.startsWith(r'\')) normalized = '\\$normalized';
    if (!normalized.endsWith(r'\')) normalized = '$normalized\\';
    return normalized;
  }

  /// The state of one optional feature, or an empty string when it is not in this image.
  Future<String> _featureState(String name) async {
    final String output = await _runPS(
      "(Get-WindowsOptionalFeature -Online -FeatureName '$name' -ErrorAction SilentlyContinue).State",
    );
    return output.trim();
  }

  /// Whether a scheduled task exists on this system.
  Future<bool> _taskExists(String taskPath, String name) async {
    final String output = await _runPS(
      "if (Get-ScheduledTask -TaskPath '$taskPath' -TaskName '$name' "
      "-ErrorAction SilentlyContinue) { 'yes' }",
    );
    return output.contains('yes');
  }

  Future<String> _runPS(String script) async {
    try {
      final ProcessResult result = await runPSCommand(
        script,
        stdout: true,
        loggerInfoOutput: false,
      );
      return result.stdout.toString();
    } catch (error) {
      logger.w('system_monitor: PowerShell query failed', error: error);
      return '';
    }
  }

  Future<void> _runPSStrict(String script) async {
    await runPSCommand(script, loggerInfoOutput: false);
  }
}
