import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mangocounter/features/history/data/history_repository.dart';
import 'package:mangocounter/features/history/domain/scan_record.dart';

void main() {
  late HistoryRepository repo;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scans (
            id TEXT PRIMARY KEY,
            created_at INTEGER,
            image_path TEXT,
            image_width INTEGER,
            image_height INTEGER,
            model_half_ripe INTEGER,
            model_ripe INTEGER,
            model_unripe INTEGER,
            edited_half_ripe INTEGER,
            edited_ripe INTEGER,
            edited_unripe INTEGER,
            actual_count INTEGER,
            conf_threshold REAL,
            iou_threshold REAL,
            inference_ms INTEGER,
            is_demo INTEGER,
            detections_json TEXT,
            model_detections_json TEXT
          )
        ''');
      }
    ));
    repo = HistoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('CRUD operations', () async {
    final record = ScanRecord(
      id: 'test-id',
      createdAt: 1000,
      imagePath: '/path/to/img.jpg',
      imageWidth: 640,
      imageHeight: 640,
      modelHalfRipe: 0,
      modelRipe: 5,
      modelUnripe: 2,
      confThreshold: 0.4,
      iouThreshold: 0.45,
      inferenceMs: 15,
      isDemo: false,
      detections: [],
      modelDetections: [],
    );

    // Insert
    await repo.insertScan(record);
    var scans = await repo.getAllScans();
    expect(scans.length, 1);
    expect(scans.first.id, 'test-id');

    // Delete
    await repo.deleteScan('test-id');
    scans = await repo.getAllScans();
    expect(scans.isEmpty, true);
  });
}
