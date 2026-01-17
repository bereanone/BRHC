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
      SELECT section_title
      FROM brhc_sections
      ORDER BY order_index
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
      SELECT DISTINCT
        q.chapter_number AS chapter_number,
        c.chapter_title AS raw_chapter_title,
        s.section_title AS raw_section_title
      FROM questions q
      JOIN brhc_sections s
        ON s.section_id = q.section_number
      JOIN brhc_chapters c
        ON c.chapter_id = q.chapter_number
      WHERE s.section_title = ?
      ORDER BY q.chapter_number
      ''',
      [sectionTitle],
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
      SELECT c.chapter_id AS chapter_number, s.order_index AS section_order
      FROM brhc_chapters c
      JOIN brhc_sections s ON s.section_id = c.section_id
      WHERE s.section_title = ?
        AND c.chapter_title = ?
      LIMIT 1
      ''',
      [sectionTitle, chapterTitle],
    );
    if (currentRows.isEmpty) return null;
    final chapterNumber = currentRows.first['chapter_number'] as int;
    final sectionOrder = currentRows.first['section_order'] as int;

    final rows = await db.rawQuery(
      '''
      SELECT
        c.chapter_id AS chapter_number,
        c.chapter_title AS raw_chapter_title,
        s.section_title AS raw_section_title
      FROM brhc_chapters c
      JOIN brhc_sections s ON s.section_id = c.section_id
      WHERE (s.order_index < ?)
         OR (s.order_index = ? AND c.chapter_id < ?)
      ORDER BY s.order_index DESC, c.chapter_id DESC
      LIMIT 1
      ''',
      [sectionOrder, sectionOrder, chapterNumber],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(row['raw_section_title'] as String),
      chapterTitle: _stripTagPrefix(row['raw_chapter_title'] as String),
      rawSectionTitle: row['raw_section_title'] as String,
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
      SELECT c.chapter_id AS chapter_number, s.order_index AS section_order
      FROM brhc_chapters c
      JOIN brhc_sections s ON s.section_id = c.section_id
      WHERE s.section_title = ?
        AND c.chapter_title = ?
      LIMIT 1
      ''',
      [sectionTitle, chapterTitle],
    );
    if (currentRows.isEmpty) return null;
    final chapterNumber = currentRows.first['chapter_number'] as int;
    final sectionOrder = currentRows.first['section_order'] as int;

    final rows = await db.rawQuery(
      '''
      SELECT
        c.chapter_id AS chapter_number,
        c.chapter_title AS raw_chapter_title,
        s.section_title AS raw_section_title
      FROM brhc_chapters c
      JOIN brhc_sections s ON s.section_id = c.section_id
      WHERE (s.order_index > ?)
         OR (s.order_index = ? AND c.chapter_id > ?)
      ORDER BY s.order_index ASC, c.chapter_id ASC
      LIMIT 1
      ''',
      [sectionOrder, sectionOrder, chapterNumber],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(row['raw_section_title'] as String),
      chapterTitle: _stripTagPrefix(row['raw_chapter_title'] as String),
      rawSectionTitle: row['raw_section_title'] as String,
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
      FROM brhc_images
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
      SELECT order_index
      FROM brhc_sections
      WHERE section_title = ?
      LIMIT 1
      ''',
      [sectionTitle],
    );
    if (currentRows.isEmpty) {
      return null;
    }
    final currentOrder = currentRows.first['order_index'] as int;
    final prevRows = await db.rawQuery(
      '''
      SELECT s.section_title, s.order_index
      FROM brhc_sections s
      JOIN questions q ON q.section_number = s.section_id
      WHERE s.order_index < ?
      GROUP BY s.section_title, s.order_index
      ORDER BY s.order_index DESC
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
      SELECT q.chapter_number, c.chapter_title AS raw_chapter_title
      FROM questions q
      JOIN brhc_chapters c ON c.chapter_id = q.chapter_number
      WHERE q.section_number = (
        SELECT section_id FROM brhc_sections WHERE section_title = ?
      )
      ORDER BY q.chapter_number ASC
      LIMIT 1
      ''',
      [prevSection],
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
      SELECT order_index
      FROM brhc_sections
      WHERE section_title = ?
      LIMIT 1
      ''',
      [sectionTitle],
    );
    if (currentRows.isEmpty) {
      return null;
    }
    final currentOrder = currentRows.first['order_index'] as int;
    final nextRows = await db.rawQuery(
      '''
      SELECT s.section_title, s.order_index
      FROM brhc_sections s
      JOIN questions q ON q.section_number = s.section_id
      WHERE s.order_index > ?
      GROUP BY s.section_title, s.order_index
      ORDER BY s.order_index ASC
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
      SELECT q.chapter_number, c.chapter_title AS raw_chapter_title
      FROM questions q
      JOIN brhc_chapters c ON c.chapter_id = q.chapter_number
      WHERE q.section_number = (
        SELECT section_id FROM brhc_sections WHERE section_title = ?
      )
      ORDER BY q.chapter_number ASC
      LIMIT 1
      ''',
      [nextSection],
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
      SELECT s.section_title
      FROM brhc_sections s
      JOIN questions q ON q.section_number = s.section_id
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
      SELECT s.section_title
      FROM brhc_sections s
      JOIN questions q ON q.section_number = s.section_id
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
