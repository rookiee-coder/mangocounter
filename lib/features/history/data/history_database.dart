import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class HistoryDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mangocount_history.db');
    return _database!;
  }

  static Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  static Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scans (
        id TEXT PRIMARY KEY,
        tree_id TEXT,
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

  static Future<void> _upgradeDB(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE scans ADD COLUMN tree_id TEXT');
    }
  }
}
