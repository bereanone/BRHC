import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/brhc_models.dart';

class BrhcDatabase {
  BrhcDatabase._();

  static final BrhcDatabase instance = BrhcDatabase._();

  Database? _database;
  Database? _userDatabase;
  String? _userDatabasePath;
  bool _auditMarksAvailable = true;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'brhc.db');
    final exists = await databaseExists(path);

    // Seed DB is opened read-only to preserve canonical data.
    if (!exists) {
      await Directory(dirname(path)).create(recursive: true);
      final data = await rootBundle.load('assets/brhc.db');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(path, readOnly: true);
    assert(() {
      _logSchemaInfo(db);
      return true;
    }());
    return db;
  }

  Future<Database> get userDatabase async {
    final existing = _userDatabase;
    if (existing != null) {
      return existing;
    }
    _userDatabase = await _openUserDatabase();
    return _userDatabase!;
  }

  Future<Database> _openUserDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'brhc_user.db');
    _userDatabasePath = path;
    // User DB is opened read/write for sandboxed audit marks.
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          '''
          CREATE TABLE IF NOT EXISTS brhc_audit_marks (
            question_id INTEGER PRIMARY KEY,
            checked INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
          ''',
        );
      },
      onOpen: (db) async {
        await db.execute(
          '''
          CREATE TABLE IF NOT EXISTS brhc_audit_marks (
            question_id INTEGER PRIMARY KEY,
            checked INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
          ''',
        );
        final columns =
            await db.rawQuery("PRAGMA table_info(brhc_audit_marks)");
        _auditMarksAvailable =
            columns.any((row) => row['name'] == 'question_id');
        if (!_auditMarksAvailable) {
          debugPrint('Audit marks disabled: question_id column missing.');
        }
      },
    );
    return db;
  }

  Future<void> _ensureUserAttached(Database seedDb) async {
    await userDatabase;
    if (!_auditMarksAvailable) {
      return;
    }
    final userPath = _userDatabasePath;
    if (userPath == null) {
      return;
    }
    final attached = await seedDb.rawQuery('PRAGMA database_list');
    final alreadyAttached = attached.any((row) => row['name'] == 'brhc_user');
    if (!alreadyAttached) {
      await seedDb.execute('ATTACH DATABASE ? AS brhc_user', [userPath]);
    }
  }

  Future<List<Section>> fetchSections() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT section_title FROM brhc_sections ORDER BY order_index',
    );
    return rows
        .map<Section>((row) => Section(title: row['section_title'] as String))
        .toList();
  }

  Future<List<Chapter>> fetchChapters(String sectionTitle) async {
    final db = await database;
    try {
      final rows = await db.rawQuery(
        '''
        SELECT
          c.chapter_id,
          c.chapter_title,
          MIN(q.question_id) AS first_question_id
        FROM brhc_chapters c
        JOIN brhc_sections s ON s.section_id = c.section_id
        JOIN brhc_questions q ON q.chapter_id = c.chapter_id
        WHERE s.section_title = ?
        GROUP BY c.chapter_id, c.chapter_title
        ORDER BY c.order_index
        ''',
        [sectionTitle],
      );
      if (rows.isEmpty) {
        debugPrint('Warning: no chapters found for section "$sectionTitle".');
      }

      return rows
          .map<Chapter>(
            (row) => Chapter(
              title: row['chapter_title'] as String,
              chapterId: row['chapter_id'] as int,
            ),
          )
          .toList();
    } catch (error) {
      debugPrint('SQL error in fetchChapters: $error');
      rethrow;
    }
  }

  Future<List<QuestionItem>> fetchQuestions({
    required int chapterId,
  }) async {
    final db = await database;
    try {
      await _ensureUserAttached(db);
      final includeMarks = _auditMarksAvailable;
      final rows = await db.rawQuery(
        includeMarks
            ? '''
            SELECT
              q.question_id,
              q.question_text,
              q.order_index,
              COALESCE(GROUP_CONCAT(a.answer_text, ' '), '') AS answer_text,
              i.image_blob,
              COALESCE(m.checked, 0) AS checked
            FROM brhc_questions q
            JOIN brhc_chapters c
              ON c.chapter_id = q.chapter_id
            LEFT JOIN brhc_answers a
              ON a.question_id = q.question_id
            LEFT JOIN brhc_images i
              ON i.chapter_number = c.order_index
             AND i.question_number = q.order_index
            LEFT JOIN brhc_user.brhc_audit_marks m
              ON m.question_id = q.question_id
            WHERE q.chapter_id = ?
            GROUP BY q.question_id, q.question_text, q.order_index, i.image_blob, m.checked
            ORDER BY q.order_index, q.question_id
            '''
            : '''
            SELECT
              q.question_id,
              q.question_text,
              q.order_index,
              COALESCE(GROUP_CONCAT(a.answer_text, ' '), '') AS answer_text,
              i.image_blob,
              0 AS checked
            FROM brhc_questions q
            JOIN brhc_chapters c
              ON c.chapter_id = q.chapter_id
            LEFT JOIN brhc_answers a
              ON a.question_id = q.question_id
            LEFT JOIN brhc_images i
              ON i.chapter_number = c.order_index
             AND i.question_number = q.order_index
            WHERE q.chapter_id = ?
            GROUP BY q.question_id, q.question_text, q.order_index, i.image_blob
            ORDER BY q.order_index, q.question_id
            ''',
        [chapterId],
      );

      return rows.map((row) {
        final blob = row['image_blob'] as Uint8List?;
        return QuestionItem(
          questionId: row['question_id'] as int,
          question: row['question_text'] as String,
          answer: row['answer_text'] as String,
          answerType: null,
          verseText: null,
          imageBytes: blob,
          checked: (row['checked'] as int?) == 1,
        );
      }).toList();
    } catch (error) {
      debugPrint('SQL error in fetchQuestions: $error');
      rethrow;
    }
  }

  Future<Chapter?> fetchPreviousChapter(int chapterId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT c.chapter_id, c.chapter_title
      FROM brhc_chapters c
      WHERE c.order_index < (
        SELECT order_index FROM brhc_chapters WHERE chapter_id = ?
      )
        AND EXISTS (
          SELECT 1 FROM brhc_questions q WHERE q.chapter_id = c.chapter_id
        )
      ORDER BY c.order_index DESC
      LIMIT 1
      ''',
      [chapterId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return Chapter(
      title: row['chapter_title'] as String,
      chapterId: row['chapter_id'] as int,
    );
  }

  Future<Chapter?> fetchNextChapter(int chapterId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT c.chapter_id, c.chapter_title
      FROM brhc_chapters c
      WHERE c.order_index > (
        SELECT order_index FROM brhc_chapters WHERE chapter_id = ?
      )
        AND EXISTS (
          SELECT 1 FROM brhc_questions q WHERE q.chapter_id = c.chapter_id
        )
      ORDER BY c.order_index ASC
      LIMIT 1
      ''',
      [chapterId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return Chapter(
      title: row['chapter_title'] as String,
      chapterId: row['chapter_id'] as int,
    );
  }

  Future<void> setAuditMark({
    required int questionId,
    required bool checked,
  }) async {
    if (!_auditMarksAvailable) {
      debugPrint('Audit marks disabled: question_id column missing.');
      return;
    }
    final db = await userDatabase;
    if (checked) {
      await db.rawInsert(
        '''
        INSERT OR REPLACE INTO brhc_audit_marks
          (question_id, checked, updated_at)
        VALUES (?, 1, CURRENT_TIMESTAMP)
        ''',
        [questionId],
      );
    } else {
      await db.rawUpdate(
        '''
        UPDATE brhc_audit_marks
        SET checked = 0, updated_at = CURRENT_TIMESTAMP
        WHERE question_id = ?
        ''',
        [questionId],
      );
    }
  }

  Future<void> _logSchemaInfo(Database db) async {
    final dbPath = await getDatabasesPath();
    debugPrint('BRHC DB path: $dbPath/brhc.db');
    final questions = await db.rawQuery('PRAGMA table_info(brhc_questions)');
    final chapters = await db.rawQuery('PRAGMA table_info(brhc_chapters)');
    debugPrint('brhc_questions schema: $questions');
    debugPrint('brhc_chapters schema: $chapters');
  }
}
