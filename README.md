# Grouped Batch Offline-First Sync

Grouped Batch Offline-First Sync is a practical synchronization pattern for multi-device offline-first applications.

It addresses a common failure mode: a single user action creates several related records, but record-by-record synchronization sends or applies those records separately. This can leave other devices with orphan records or incomplete business operations.

The core rule is simple:

> Technical batches optimize transport. Operation groups preserve business meaning.

## Problem

In offline-first systems, local writes usually enter a sync queue and are sent later. That works when one user action creates one record.

It becomes fragile when one user action creates multiple related records:

- a receipt creates a payment and a financial entry;
- a sale creates an order, inventory changes, and payment data;
- a deletion creates cleanup or reversal records;
- a table order creates items, status changes, and notifications.

If those records are synchronized independently, another device may receive only part of the operation.

## Method

Grouped Batch Sync adds an operation group to the local sync queue.

1. A user action opens an operation context.
2. The context creates a `syncGroupId`.
3. Every local change created inside that context enters the queue with the same group.
4. The sync orchestrator builds technical batches.
5. Records with the same `syncGroupId` are kept together when batches are built.

This means a logical group may exceed the technical `batchSize`. That is intentional: batch size is a transport optimization, not a business boundary.

## Minimal Output

With `batchSize: 2`, a grouped receipt operation with three records is still sent together:

```text
Batch 1 (3 records)
- receipts:receipt-001 action=upsert group=receipt-create / receipt-create:receipt-001:...
- payments:payment-001 action=upsert group=receipt-create / receipt-create:receipt-001:...
- financial_entries:entry-001 action=upsert group=receipt-create / receipt-create:receipt-001:...

Batch 2 (2 records)
- products:product-001 action=upsert group=no-group
- customers:customer-001 action=upsert group=no-group
```

## What It Helps With

- Reducing orphan records.
- Reducing incomplete states across devices.
- Keeping composite business operations coherent.
- Making sync failures easier to trace by operation group.
- Making offline-first behavior more predictable.

## What It Does Not Replace

Grouped Batch Sync does not remove the need for:

- conflict detection and resolution;
- versioning;
- idempotent endpoints;
- server-side validation;
- retry handling;
- deletion semantics;
- observability;
- database transactions when true server-side atomicity is required.

## Files

- [Technical document in Portuguese](docs/grouped-batch-offline-first-sync.pt.md)
- [Technical document in English](docs/grouped-batch-offline-first-sync.en.md)
- [Publication-ready article](articles/grouped-batch-sync-reducing-orphan-records.md)
- [Minimal Dart example](examples/grouped_batch_sync_example.dart)

## Suggested Public Positioning

Grouped Batch Sync should not be presented as a universal solution for all offline-first synchronization problems.

A stronger and more defensible positioning is:

> Grouped Batch Sync reduces orphan records and incomplete states caused by synchronizing composite business operations as isolated records.

