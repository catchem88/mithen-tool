import 'package:flutter_test/flutter_test.dart';
import 'package:revitool/features/cleanup/domain/entities/orphan_item.dart';

void main() {
  group('CleanupReport', () {
    test('groups the leftovers by kind', () {
      final report = CleanupReport(
        items: <OrphanItem>[
          _item('a', OrphanKind.service),
          _item('b', OrphanKind.folder),
          _item('c', OrphanKind.service),
        ],
        scannedAt: DateTime(2026),
      );

      expect(report.total, 3);
      expect(report.ofKind(OrphanKind.service).length, 2);
      expect(report.countOfKind(OrphanKind.folder), 1);
      expect(report.ofKind(OrphanKind.registry), isEmpty);
    });
  });

  group('OrphanItem', () {
    test('defaults to a safe selection', () {
      final item = _item('a', OrphanKind.service);

      expect(item.confidence, OrphanConfidence.high);
      expect(item.selectedByDefault, isTrue);
      expect(item.quarantineOnly, isFalse);
    });
  });

  group('CleanupOutcome', () {
    test('counts removals and failures', () {
      final outcome = CleanupOutcome(
        results: <OrphanActionResult>[
          OrphanActionResult(item: _item('a', OrphanKind.service), ok: true),
          OrphanActionResult(item: _item('b', OrphanKind.folder), ok: false, message: 'locked'),
        ],
        backupPath: r'C:\backup',
      );

      expect(outcome.removed, 1);
      expect(outcome.failed, 1);
    });
  });
}

OrphanItem _item(String id, OrphanKind kind) =>
    OrphanItem(id: id, kind: kind, title: id, detail: id, target: id);
