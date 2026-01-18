import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/brhc_models.dart';
import '../startup/startup_data_verification.dart';

class BrhcDatabase {
  BrhcDatabase._();

  static final BrhcDatabase instance = BrhcDatabase._();

  Database? _seedDb;
  Database? _userDb;
  Future<Database>? _seedOpening;
  Future<Database>? _userOpening;

  String _normalizeSectionTitleForMatch(String value) {
    var normalized = _stripTagPrefix(value);
    normalized =
        normalized.replaceFirst(RegExp(r'^Section\s+\d+\s*[-.]?\s*'), '');
    return normalized.trim();
  }

  String _normalizeChapterTitleForMatch(String value) {
    return value.replaceFirst(RegExp(r'^\s*\[Ch\]\s*'), '').trim();
  }

  String _placeholders(int count) {
    return List.filled(count, '?').join(',');
  }

  String _stripTagPrefix(String value) {
    return value.replaceFirst(RegExp(r'^\s*\[[A-Za-z]+\]\s*'), '').trim();
  }

  String _cleanBlockText(String value) {
    return value.replaceFirst(RegExp(r'^\s*\[[A-Za-z]+\]\s*'), '');
  }

  Future<Database> get database async {
    final existing = _seedDb;
    if (existing != null) {
      return existing;
    }
    _seedOpening ??= _openSeedDb();
    _seedDb = await _seedOpening!;
    _seedOpening = null;
    return _seedDb!;
  }

  Future<Database> get userDatabase async {
    final existing = _userDb;
    if (existing != null) {
      return existing;
    }
    _userOpening ??= _openUserDb();
    _userDb = await _userOpening!;
    _userOpening = null;
    return _userDb!;
  }

  Future<Directory> _resolveDbDirectory() async {
    final dbDir = await resolveStartupSandboxDirectory();
    debugPrint('BRHC DB directory: ${dbDir.path}');
    return dbDir;
  }

  Future<Database> _openUserDb() async {
    final dbDir = await _resolveDbDirectory();
    final path = join(dbDir.path, 'brhc_user.db');
    debugPrint('BRHC user DB path: $path');
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('BRHC user DB missing: $path');
    }
    final size = await file.length();
    debugPrint('BRHC user DB size: $size');
    if (size == 0) {
      throw StateError('BRHC user DB empty: $path');
    }
    return openDatabase(
      path,
      version: 1,
    );
  }

  Future<double> fetchFontScale() async {
    try {
      final db = await userDatabase;
      final rows = await db.rawQuery(
        'SELECT value FROM user_settings WHERE "key" = ? LIMIT 1',
        ['font_scale'],
      );
      if (rows.isEmpty) {
        return 1.0;
      }
      final value = rows.first['value']?.toString();
      final parsed = double.tryParse(value ?? '');
      return parsed ?? 1.0;
    } catch (error) {
      debugPrint('Font scale read failed: $error');
      return 1.0;
    }
  }

  Future<void> setFontScale(double scale) async {
    try {
      final db = await userDatabase;
      await db.rawInsert(
        'INSERT OR REPLACE INTO user_settings ("key", value) VALUES (?, ?)',
        ['font_scale', scale.toString()],
      );
    } catch (error) {
      debugPrint('Font scale write failed: $error');
    }
  }

  Future<Database> _openSeedDb() async {
    await userDatabase;

    final dbDir = await _resolveDbDirectory();
    final path = join(dbDir.path, 'brhc.db');

    final file = File(path);
    debugPrint('BRHC seed DB path: $path');
    if (!await file.exists()) {
      throw StateError('BRHC seed DB missing: $path');
    }
    final size = await file.length();
    debugPrint('BRHC seed DB size: $size');
    if (size == 0) {
      throw StateError('BRHC seed DB empty: $path');
    }

    return openDatabase(
      path,
      readOnly: true,
    );
  }

  Future<List<Section>> fetchSections() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT section_number, section_title
      FROM questions
      ORDER BY section_number
      ''',
    );
    return rows
        .map<Section>((row) {
          final rawTitle = row['section_title'] as String;
          return Section(
            title: _stripTagPrefix(rawTitle),
            rawTitle: rawTitle,
          );
        })
        .toList();
  }

  Future<List<ChapterEntry>> fetchChapters(String sectionTitle) async {
    final db = await database;

    final rows = await db.rawQuery(
      '''
      WITH current_section AS (
        SELECT section_number, MIN(chapter_id) AS min_chapter
        FROM questions
        WHERE section_title = ?
        GROUP BY section_number
      ),
      next_section AS (
        SELECT MIN(chapter_id) AS next_min_chapter
        FROM questions
        WHERE section_number > (SELECT section_number FROM current_section)
      )
      SELECT
        c.chapter_id AS chapter_number,
        c.chapter_title AS raw_chapter_title,
        ? AS raw_section_title
      FROM chapters c
      WHERE c.chapter_id >= (SELECT min_chapter FROM current_section)
        AND (
          (SELECT next_min_chapter FROM next_section) IS NULL
          OR c.chapter_id < (SELECT next_min_chapter FROM next_section)
        )
      ORDER BY c.chapter_id
      ''',
      [sectionTitle, sectionTitle],
    );

    return rows.map<ChapterEntry>((row) {
      final rawChapterTitle = row['raw_chapter_title'] as String;
      final rawSectionTitle = row['raw_section_title'] as String;
      return ChapterEntry(
        sectionTitle: _stripTagPrefix(rawSectionTitle),
        chapterTitle: _stripTagPrefix(rawChapterTitle),
        rawSectionTitle: rawSectionTitle,
        rawChapterTitle: rawChapterTitle,
        firstBlockId: 0,
      );
    }).toList();
  }


  Future<ChapterEntry?> fetchPreviousChapter({
    required String sectionTitle,
    required String chapterTitle,
  }) async {
    final db = await database;

    final currentRows = await db.rawQuery(
      '''
      SELECT chapter_id AS chapter_number
      FROM chapters
      WHERE chapter_title = ?
      LIMIT 1
      ''',
      [chapterTitle],
    );
    if (currentRows.isEmpty) return null;
    final chapterNumber = currentRows.first['chapter_number'] as int;

    final rows = await db.rawQuery(
      '''
      SELECT
        chapter_id AS chapter_number,
        chapter_title AS raw_chapter_title
      FROM chapters
      WHERE chapter_id < ?
      ORDER BY chapter_id DESC
      LIMIT 1
      ''',
      [chapterNumber],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(sectionTitle),
      chapterTitle: _stripTagPrefix(row['raw_chapter_title'] as String),
      rawSectionTitle: sectionTitle,
      rawChapterTitle: row['raw_chapter_title'] as String,
      firstBlockId: 0,
    );
  }

  Future<ChapterEntry?> fetchNextChapter({
    required String sectionTitle,
    required String chapterTitle,
  }) async {
    final db = await database;

    final currentRows = await db.rawQuery(
      '''
      SELECT chapter_id AS chapter_number
      FROM chapters
      WHERE chapter_title = ?
      LIMIT 1
      ''',
      [chapterTitle],
    );
    if (currentRows.isEmpty) return null;
    final chapterNumber = currentRows.first['chapter_number'] as int;

    final rows = await db.rawQuery(
      '''
      SELECT
        chapter_id AS chapter_number,
        chapter_title AS raw_chapter_title
      FROM chapters
      WHERE chapter_id > ?
      ORDER BY chapter_id ASC
      LIMIT 1
      ''',
      [chapterNumber],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(sectionTitle),
      chapterTitle: _stripTagPrefix(row['raw_chapter_title'] as String),
      rawSectionTitle: sectionTitle,
      rawChapterTitle: row['raw_chapter_title'] as String,
      firstBlockId: 0,
    );
  }

  Future<List<DocBlock>> fetchIntroductionBlocks() async {
    return [];
  }

  Future<Uint8List?> fetchImageBlobByFilename(String filename) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT image_blob
      FROM images
      WHERE LOWER(filename) = LOWER(?)
      LIMIT 1
      ''',
      [filename],
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['image_blob'] as Uint8List?;
  }

  Future<ChapterEntry?> fetchPreviousSectionWithContent({
    required String sectionTitle,
  }) async {
    final db = await database;
    final currentRows = await db.rawQuery(
      '''
      SELECT section_number
      FROM questions
      WHERE section_title = ?
      ORDER BY section_number ASC
      LIMIT 1
      ''',
      [sectionTitle],
    );
    if (currentRows.isEmpty) {
      return null;
    }
    final currentOrder = currentRows.first['section_number'] as int;
    final prevRows = await db.rawQuery(
      '''
      SELECT DISTINCT q.section_title, q.section_number
      FROM questions q
      WHERE q.section_number < ?
      ORDER BY q.section_number DESC
      LIMIT 1
      ''',
      [currentOrder],
    );
    if (prevRows.isEmpty) {
      return null;
    }
    final prevSection = prevRows.first['section_title'] as String;
    final chapterRows = await db.rawQuery(
      '''
      SELECT DISTINCT q.chapter_id, c.chapter_title AS raw_chapter_title
      FROM questions q
      JOIN chapters c ON c.chapter_id = q.chapter_id
      WHERE q.section_number = ?
      ORDER BY q.chapter_id ASC
      LIMIT 1
      ''',
      [prevRows.first['section_number']],
    );
    if (chapterRows.isEmpty) {
      return null;
    }
    final rawChapterTitle = chapterRows.first['raw_chapter_title'] as String;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(prevSection),
      chapterTitle: _stripTagPrefix(rawChapterTitle),
      rawSectionTitle: prevSection,
      rawChapterTitle: rawChapterTitle,
      firstBlockId: 0,
    );
  }

  Future<ChapterEntry?> fetchNextSectionWithContent({
    required String sectionTitle,
  }) async {
    final db = await database;
    final currentRows = await db.rawQuery(
      '''
      SELECT section_number
      FROM questions
      WHERE section_title = ?
      ORDER BY section_number ASC
      LIMIT 1
      ''',
      [sectionTitle],
    );
    if (currentRows.isEmpty) {
      return null;
    }
    final currentOrder = currentRows.first['section_number'] as int;
    final nextRows = await db.rawQuery(
      '''
      SELECT DISTINCT q.section_title, q.section_number
      FROM questions q
      WHERE q.section_number > ?
      ORDER BY q.section_number ASC
      LIMIT 1
      ''',
      [currentOrder],
    );
    if (nextRows.isEmpty) {
      return null;
    }
    final nextSection = nextRows.first['section_title'] as String;
    final chapterRows = await db.rawQuery(
      '''
      SELECT DISTINCT q.chapter_id, c.chapter_title AS raw_chapter_title
      FROM questions q
      JOIN chapters c ON c.chapter_id = q.chapter_id
      WHERE q.section_number = ?
      ORDER BY q.chapter_id ASC
      LIMIT 1
      ''',
      [nextRows.first['section_number']],
    );
    if (chapterRows.isEmpty) {
      return null;
    }
    final rawChapterTitle = chapterRows.first['raw_chapter_title'] as String;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(nextSection),
      chapterTitle: _stripTagPrefix(rawChapterTitle),
      rawSectionTitle: nextSection,
      rawChapterTitle: rawChapterTitle,
      firstBlockId: 0,
    );
  }
  // Backward-compatibility wrappers (do not change logic)
  Future<ChapterEntry?> fetchPreviousSectionWithContentByBlock({
    required int blockId,
  }) async {
    // blockId is not needed for section lookup in current schema
    // Delegate to section-based navigation
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT q.section_title
      FROM questions q
      JOIN answer_blocks ab ON ab.question_id = q.id
      WHERE ab.id < ?
      ORDER BY ab.id DESC
      LIMIT 1
      ''',
      [blockId],
    );
    if (rows.isEmpty) return null;
    return fetchPreviousSectionWithContent(
      sectionTitle: rows.first['section_title'] as String,
    );
  }

  Future<ChapterEntry?> fetchNextSectionWithContentByBlock({
    required int blockId,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT q.section_title
      FROM questions q
      JOIN answer_blocks ab ON ab.question_id = q.id
      WHERE ab.id > ?
      ORDER BY ab.id ASC
      LIMIT 1
      ''',
      [blockId],
    );
    if (rows.isEmpty) return null;
    return fetchNextSectionWithContent(
      sectionTitle: rows.first['section_title'] as String,
    );
  }
}
