/// Kind of system state a [MonitorItem] verifies.
enum MonitorCheckKind() {
  appx,
  service,
  feature,
  task,
  registry,
  hosts,
}

/// Expected state for a [MonitorItem].
enum MonitorExpected() {
  /// The AppX package must not be installed for any user.
  absent,

  /// A Windows optional feature or scheduled task must be disabled.
  disabled,

  /// A Windows optional feature must be enabled.
  enabled,

  /// The registry value must equal the expected data.
  value,

  /// The registry value must not exist.
  valueAbsent,

  /// The hosts file must contain the expected entry.
  hostsEntry,
}

/// A single item from the System Monitor manifest.
final class const MonitorItem({
  /// Stable identifier, also used as the CLI key.
  required final String id,
  required final MonitorCheckKind kind,

  /// AppX package name, service name, feature name, task name or a short label.
  required final String name,
  required final MonitorExpected expected,

  /// Whether the registry check targets HKCU instead of HKLM.
  final bool userHive = false,

  /// Service name (when [kind] is [MonitorCheckKind.service]).
  final String? service,

  /// Task folder (when [kind] is [MonitorCheckKind.task]).
  final String? taskPath,
  final String? registryPath,
  final String? registryValue,

  /// `dword` or `string` (when [kind] is [MonitorCheckKind.registry]).
  final String? registryType,

  /// Expected registry data or hosts entry.
  final String? expectedData,

  /// Expected startup type (4 = disabled, 3 = manual, 2 = automatic).
  final int? expectedStart,

  /// Whether the item can be restored automatically by the Fix action.
  final bool autoFix = true,

  /// Short note shown under the title to preempt common concerns.
  final String? description,
}) {
  /// Action-style label shown in the UI, for example `Remove Microsoft.ZuneMusic`.
  String get title {
    switch (kind) {
      case MonitorCheckKind.appx:
        return 'Remove $name';
      case MonitorCheckKind.service:
        return 'Set $name to ${switch (expectedStart) {
          4 => 'disabled',
          3 => 'manual',
          2 => 'automatic',
          _ => 'the expected start type',
        }}';
      case MonitorCheckKind.feature:
        return expected == MonitorExpected.enabled ? 'Enable $name' : 'Disable $name';
      case MonitorCheckKind.task:
        return expected == MonitorExpected.disabled ? 'Disable $name' : 'Enable $name';
      case MonitorCheckKind.registry:
        final String? value = registryValue;
        if (value == null || value.isEmpty) return name;
        return expected == MonitorExpected.valueAbsent ? 'Remove $value' : 'Set $value';
      case MonitorCheckKind.hosts:
        return 'Hosts: $name';
    }
  }
}

/// Result of evaluating a single [MonitorItem].
final class const MonitorResult({
  required final MonitorItem item,
  required final bool ok,

  /// Detected state, shown in the UI when it differs from the expectation.
  final String? actual,

  /// Set when the check itself failed (for example a PowerShell error).
  final String? error,
});

/// Aggregated result of a full System Monitor scan.
final class const MonitorReport({
  required final List<MonitorResult> results,
  required final DateTime scannedAt,
}) {
  int get total => results.length;
  int get okCount => results.where((result) => result.ok).length;
  int get driftedCount => total - okCount;
  bool get allOk => driftedCount == 0;
}
