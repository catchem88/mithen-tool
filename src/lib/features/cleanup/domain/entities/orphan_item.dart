/// Category of leftover found by the cleanup scan.
enum OrphanKind() {
  uninstallEntry,
  fileAssociation,
  registry,
  folder,
  scheduledTask,
  service,
  startupEntry,
}

/// How safe an item is to remove without a second look.
enum OrphanConfidence() {
  high,
  medium,
  low,
}

/// A single leftover found on the system.
final class const OrphanItem({
  required final String id,
  required final OrphanKind kind,
  required final String title,
  required final String detail,
  required final String target,
  final String? appName,
  final String? publisher,
  final OrphanConfidence confidence = OrphanConfidence.high,
  final bool selectedByDefault = true,
  final bool quarantineOnly = false,
});

/// Result of a cleanup scan.
final class const CleanupReport({
  required final List<OrphanItem> items,
  required final DateTime scannedAt,
}) {
  int get total => items.length;

  List<OrphanItem> ofKind(OrphanKind kind) =>
      items.where((OrphanItem item) => item.kind == kind).toList(growable: false);

  int countOfKind(OrphanKind kind) => ofKind(kind).length;
}

/// Thrown when the user cancels a scan from the skip/cancel prompt.
final class const ScanCancelledException() implements Exception {
  @override
  String toString() => 'The scan was cancelled';
}

/// Outcome for one item after a cleanup run.
final class const OrphanActionResult({
  required final OrphanItem item,
  required final bool ok,
  final String? message,
});

/// Outcome of a cleanup run.
final class const CleanupOutcome({
  required final List<OrphanActionResult> results,
  required final String backupPath,
}) {
  int get removed => results.where((OrphanActionResult result) => result.ok).length;
  int get failed => results.length - removed;
}

/// One removal pass of a fixpoint run.
final class const CleanupPassResult({
  required final int pass,
  required final int removed,
  required final int failed,
  required final List<OrphanActionResult> results,
});

/// Aggregated result of a multi-pass cleanup run.
///
/// [remaining] lists what a final verification scan still found (failed items
/// plus anything the OS recreated) - empty means the system came out clean.
final class const CleanupRunResult({
  required final List<CleanupPassResult> passes,
  required final List<OrphanItem> remaining,
  required final String backupPath,
});
