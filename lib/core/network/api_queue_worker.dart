import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

typedef ApiQueueJob = Future<void> Function();

class _QueuedJob {
  _QueuedJob({
    required this.key,
    required this.job,
    required this.maxAttempts,
  });

  final String key;
  final ApiQueueJob job;
  final int maxAttempts;
  int attempts = 0;
}

/// طابور عامل واحد لطلبات الشبكة — يمنع تداخل الاستطلاعات ويعيد المحاولة بهدوء.
class ApiQueueWorker {
  ApiQueueWorker._();

  static final ApiQueueWorker instance = ApiQueueWorker._();

  final Queue<_QueuedJob> _queue = Queue<_QueuedJob>();
  final Set<String> _inflightOrQueued = <String>{};
  bool _pumping = false;

  /// يضيف مهمة. مع [coalesce]=true تُتجاهل إن وُجدت مهمة بنفس المفتاح قيد الانتظار/التنفيذ.
  void enqueue(
    ApiQueueJob job, {
    required String key,
    bool coalesce = true,
    int maxAttempts = 3,
  }) {
    if (coalesce && _inflightOrQueued.contains(key)) {
      return;
    }
    _inflightOrQueued.add(key);
    _queue.add(
      _QueuedJob(key: key, job: job, maxAttempts: maxAttempts),
    );
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeFirst();
        item.attempts++;
        try {
          await item.job();
          _inflightOrQueued.remove(item.key);
        } catch (e, st) {
          debugPrint('ApiQueueWorker[${item.key}] attempt ${item.attempts}: $e');
          if (item.attempts < item.maxAttempts) {
            await Future<void>.delayed(
              Duration(milliseconds: 400 * item.attempts),
            );
            _queue.addFirst(item);
          } else {
            _inflightOrQueued.remove(item.key);
            debugPrint('ApiQueueWorker[${item.key}] gave up\n$st');
          }
        }
      }
    } finally {
      _pumping = false;
      if (_queue.isNotEmpty) unawaited(_pump());
    }
  }
}
