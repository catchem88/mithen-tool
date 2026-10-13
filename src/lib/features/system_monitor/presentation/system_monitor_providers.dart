import 'package:riverpod/riverpod.dart';

import '../data/system_monitor_repository.dart';
import '../domain/entities/monitor_item.dart';

/// Provides the [SystemMonitorRepository].
final systemMonitorRepositoryProvider = Provider<SystemMonitorRepository>(
  (ref) => const SystemMonitorRepository(),
);

/// Runs a full scan; invalidate it to re-scan.
final systemMonitorReportProvider = FutureProvider<MonitorReport>(
  (ref) => ref.watch(systemMonitorRepositoryProvider).scan(),
);
