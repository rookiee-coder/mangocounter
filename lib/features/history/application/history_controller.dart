import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/history_repository.dart';
import '../domain/scan_record.dart';

final historyRepositoryProvider = Provider<HistoryRepository?>((ref) {
  return null;
});

class HistoryController extends StateNotifier<AsyncValue<List<ScanRecord>>> {
  final HistoryRepository? repo;

  HistoryController(this.repo) : super(const AsyncValue.loading()) {
    loadScans();
  }

  Future<void> loadScans() async {
    if (repo == null) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final scans = await repo!.getAllScans();
      state = AsyncValue.data(scans);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addScan(ScanRecord scan) async {
    if (repo != null) {
      await repo!.insertScan(scan);
    }
    await loadScans();
  }

  Future<void> updateScan(ScanRecord scan) async {
    if (repo != null) {
      await repo!.updateScan(scan);
    }
    await loadScans();
  }

  Future<void> deleteScan(String id) async {
    if (repo != null) {
      await repo!.deleteScan(id);
    }
    await loadScans();
  }

  Future<void> clearHistory() async {
    if (repo != null) {
      await repo!.clearAll();
    }
    await loadScans();
  }
}

final historyProvider = StateNotifierProvider<HistoryController, AsyncValue<List<ScanRecord>>>((ref) {
  final repo = ref.watch(historyRepositoryProvider);
  return HistoryController(repo);
});
