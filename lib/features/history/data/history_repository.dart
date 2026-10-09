import 'package:sqflite/sqflite.dart';
import '../domain/scan_record.dart';

class HistoryRepository {
  final Database db;
  
  HistoryRepository(this.db);

  Future<void> insertScan(ScanRecord scan) async {
    await db.insert('scans', scan.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ScanRecord>> getAllScans() async {
    final result = await db.query('scans', orderBy: 'created_at DESC');
    return result.map((e) => ScanRecord.fromMap(e)).toList();
  }
  
  Future<void> updateScan(ScanRecord scan) async {
    await db.update('scans', scan.toMap(), where: 'id = ?', whereArgs: [scan.id]);
  }

  Future<void> deleteScan(String id) async {
    await db.delete('scans', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    await db.delete('scans');
  }
}
