import 'dart:async';

/// Minimal, framework-free example of Grouped Batch Offline-First Sync.
///
/// This file is intentionally independent from Flutter, Hive, HTTP clients, or
/// the production app. It demonstrates the core idea:
///
/// - local changes enter a queue;
/// - related changes receive the same syncGroupId;
/// - the orchestrator sends technical batches;
/// - records from the same logical operation are not split across batches.
Future<void> main() async {
  final queue = LocalSyncQueue();
  final syncApi = FakeSyncApi();
  final orchestrator = SyncOrchestrator(queue: queue, api: syncApi);

  await SyncOperationContext.run(
    groupId: SyncOperationContext.createGroupId(
      type: 'receipt-create',
      rootId: 'receipt-001',
    ),
    groupType: 'receipt-create',
    action: () async {
      queue.upsert('receipts', 'receipt-001', {'total': 120.0});
      queue.upsert('payments', 'payment-001', {
        'receiptId': 'receipt-001',
        'amount': 120.0,
      });
      queue.upsert('financial_entries', 'entry-001', {
        'reference': 'receipt-001',
        'amount': 120.0,
      });
    },
  );

  queue.upsert('products', 'product-001', {'name': 'Paper roll'});
  queue.upsert('customers', 'customer-001', {'name': 'Ada'});

  await orchestrator.flushPending(batchSize: 2);
}

class SyncOperationContext {
  static const _groupIdKey = #groupedBatchSyncGroupId;
  static const _groupTypeKey = #groupedBatchSyncGroupType;

  const SyncOperationContext._();

  static String? get groupId => Zone.current[_groupIdKey] as String?;
  static String? get groupType => Zone.current[_groupTypeKey] as String?;

  static String createGroupId({required String type, required String rootId}) {
    final cleanType = _clean(type);
    final cleanRoot = _clean(rootId);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$cleanType:$cleanRoot:$timestamp';
  }

  static Future<T> run<T>({
    required String groupId,
    required String groupType,
    required Future<T> Function() action,
  }) {
    return runZoned(
      action,
      zoneValues: {_groupIdKey: groupId, _groupTypeKey: groupType},
    );
  }

  static String _clean(String value) {
    return value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
  }
}

class LocalSyncQueue {
  final Map<String, QueueItem> _itemsByKey = {};

  List<QueueItem> get pendingItems {
    final items = _itemsByKey.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  void upsert(String entity, String id, Map<String, Object?> payload) {
    _enqueue(entity, id, 'upsert', payload);
  }

  void delete(
    String entity,
    String id, [
    Map<String, Object?> payload = const {},
  ]) {
    _enqueue(entity, id, 'delete', payload);
  }

  void remove(String queueId) {
    _itemsByKey.remove(queueId);
  }

  void _enqueue(
    String entity,
    String id,
    String action,
    Map<String, Object?> payload,
  ) {
    final queueId = '$entity:$id';
    final now = DateTime.now();
    final existing = _itemsByKey[queueId];

    _itemsByKey[queueId] = QueueItem(
      queueId: queueId,
      entity: entity,
      id: id,
      action: action,
      payload: {...payload, 'id': id},
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      syncGroupId: SyncOperationContext.groupId,
      syncGroupType: SyncOperationContext.groupType,
    );
  }
}

class SyncOrchestrator {
  final LocalSyncQueue queue;
  final FakeSyncApi api;

  const SyncOrchestrator({required this.queue, required this.api});

  Future<void> flushPending({required int batchSize}) async {
    final items = queue.pendingItems;
    final batches = _chunkPendingItems(items, batchSize);

    for (final batch in batches) {
      await api.push(batch);
      for (final item in batch) {
        queue.remove(item.queueId);
      }
    }
  }

  List<List<QueueItem>> _chunkPendingItems(
    List<QueueItem> items,
    int batchSize,
  ) {
    final batches = <List<QueueItem>>[];
    var current = <QueueItem>[];
    final consumed = <String>{};

    void flush() {
      if (current.isEmpty) return;
      batches.add(current);
      current = <QueueItem>[];
    }

    for (final item in items) {
      if (consumed.contains(item.queueId)) continue;

      final groupId = item.syncGroupId ?? '';
      final nextItems = groupId.isEmpty
          ? [item]
          : items
                .where(
                  (candidate) =>
                      !consumed.contains(candidate.queueId) &&
                      candidate.syncGroupId == groupId,
                )
                .toList();

      final wouldExceed =
          current.isNotEmpty && current.length + nextItems.length > batchSize;
      if (wouldExceed) {
        flush();
      }

      current.addAll(nextItems);
      consumed.addAll(nextItems.map((item) => item.queueId));

      if (current.length >= batchSize) {
        flush();
      }
    }

    flush();
    return batches;
  }
}

class FakeSyncApi {
  int _batchNumber = 0;

  Future<void> push(List<QueueItem> items) async {
    _batchNumber++;

    print('Batch $_batchNumber (${items.length} records)');
    for (final item in items) {
      final group = item.syncGroupType == null
          ? 'no-group'
          : '${item.syncGroupType} / ${item.syncGroupId}';
      print('- ${item.queueId} action=${item.action} group=$group');
    }
    print('');
  }
}

class QueueItem {
  final String queueId;
  final String entity;
  final String id;
  final String action;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? syncGroupId;
  final String? syncGroupType;

  const QueueItem({
    required this.queueId,
    required this.entity,
    required this.id,
    required this.action,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    required this.syncGroupId,
    required this.syncGroupType,
  });

  bool get deleted => action == 'delete';
}
