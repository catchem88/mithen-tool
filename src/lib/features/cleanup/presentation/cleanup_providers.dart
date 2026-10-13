import 'package:riverpod/riverpod.dart';

import '../data/cleanup_repository.dart';
import '../domain/entities/orphan_item.dart';

/// Provides the [CleanupRepository].
final cleanupRepositoryProvider = Provider<CleanupRepository>((ref) => const CleanupRepository());

/// Runs a cleanup scan; invalidate it to re-scan.
final cleanupScanProvider = FutureProvider<CleanupReport>(
  (ref) => ref.watch(cleanupRepositoryProvider).scan(),
);

/// Ids of the leftovers the user selected for removal.
final cleanupSelectionProvider = NotifierProvider<CleanupSelection, Set<String>>(
  CleanupSelection.new,
);

/// Keeps the selection in sync with the latest scan.
final class CleanupSelection() extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void reset(Iterable<OrphanItem> items) {
    state = <String>{
      for (final OrphanItem item in items)
        if (item.selectedByDefault) item.id,
    };
  }

  void toggle(String id) {
    state = state.contains(id) ? (<String>{...state}..remove(id)) : <String>{...state, id};
  }

  void clear() => state = const <String>{};
}
