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

  Future<List<String>> _resolveSectionTitles(
    Database db,
    String sectionTitle,
  ) async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT section_title FROM doc_blocks WHERE section_title IS NOT NULL',
    );
    final matches = rows
        .map((row) => row['section_title'] as String)
        .where(
          (title) => _normalizeSectionTitleForMatch(title) == sectionTitle,
        )
        .toList();
    if (matches.isEmpty) {
      matches.add(sectionTitle);
    }
    return matches;
  }

  Future<List<String>> _resolveChapterTitles(
    Database db,
    List<String> sectionTitles,
    String chapterTitle,
  ) async {
    if (sectionTitles.isEmpty) {
      return [chapterTitle];
    }
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT chapter_title
      FROM doc_blocks
      WHERE section_title IN (${_placeholders(sectionTitles.length)})
        AND chapter_title IS NOT NULL
      ''',
      sectionTitles,
    );
    final target = _normalizeChapterTitleForMatch(chapterTitle);
    final matches = rows
        .map((row) => row['chapter_title'] as String)
        .where(
          (title) => _normalizeChapterTitleForMatch(title) == target,
        )
        .toList();
    if (matches.isEmpty) {
      matches.add(chapterTitle);
    }
    return matches;
  }

  String _stripTagPrefix(String value) {
    return value.replaceFirst(RegExp(r'^\s*\[[A-Za-z]+\]\s*'), '').trim();
  }

  String _cleanBlockText(String value) {
    return value.replaceFirst(RegExp(r'^\s*\[[A-Za-z]+\]\s*'), '').trim();
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

  Future<Database> _openUserDb() async {
    final dbDir = await getDatabasesPath();
    await Directory(dbDir).create(recursive: true);
    final path = join(dbDir, 'brhc_user.db');
    debugPrint('BRHC user DB path: $path');
    if (!File(path).existsSync()) {
      try {
        final data = await rootBundle.load('assets/databases/brhc_user.db');
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      } catch (_) {}
    }
    return openDatabase(
      path,
      version: 1,
    );
  }

  Future<Database> _openSeedDb() async {
    // Ensure sandbox is initialized by opening user DB first
    await _openUserDb();

    final dbDir = await getDatabasesPath();
    await Directory(dbDir).create(recursive: true);
    final path = join(dbDir, 'brhc.db');

    final file = File(path);
    debugPrint('BRHC seed DB path: $path');
    if (file.existsSync()) {
      debugPrint('BRHC seed DB exists: true');
      debugPrint('BRHC seed DB size: ${file.lengthSync()}');
    } else {
      debugPrint('BRHC seed DB exists: false');
    }
    if (!file.existsSync()) {
      final data = await rootBundle.load('assets/databases/brhc.db');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes, flush: true);
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
    try {
      final sectionTitles = await _resolveSectionTitles(db, sectionTitle);
      if (sectionTitles.isEmpty) {
        return [];
      }
      final rows = await db.rawQuery(
        '''
        SELECT
          chapter_title,
          MIN(block_id) AS first_block
        FROM doc_blocks
        WHERE section_title IS NOT NULL
          AND chapter_title IS NOT NULL
          AND chapter_title <> ''
          AND section_title IN (${_placeholders(sectionTitles.length)})
        GROUP BY chapter_title
        ORDER BY first_block
        ''',
        sectionTitles,
      );
      if (rows.isEmpty) {
        debugPrint('Warning: no chapters found for section "$sectionTitle".');
      }

      return rows
          .map<ChapterEntry>(
            (row) {
              final rawChapterTitle = row['chapter_title'] as String;
              return ChapterEntry(
                sectionTitle: _stripTagPrefix(sectionTitle),
                chapterTitle: _stripTagPrefix(rawChapterTitle),
                rawSectionTitle: sectionTitle,
                rawChapterTitle: rawChapterTitle,
                firstBlockId: (row['first_block'] as int?) ?? 0,
              );
            },
          )
          .toList();
    } catch (error) {
      debugPrint('SQL error in fetchChapters: $error');
      rethrow;
    }
  }

  Future<List<DocBlock>> fetchChapterBlocks({
    required String sectionTitle,
    required String chapterTitle,
  }) async {
    final db = await database;
    try {
      final sectionTitles = await _resolveSectionTitles(db, sectionTitle);
      final chapterTitles =
          await _resolveChapterTitles(db, sectionTitles, chapterTitle);
      if (sectionTitles.isEmpty || chapterTitles.isEmpty) {
        return [];
      }
      final minRow = await db.rawQuery(
        '''
        SELECT MIN(block_id) AS first_block
        FROM doc_blocks
        WHERE section_title IN (${_placeholders(sectionTitles.length)})
        ''',
        sectionTitles,
      );
      final minBlock = (minRow.first['first_block'] as int?) ?? 0;
      final rows = await db.rawQuery(
        '''
        SELECT
          block_id,
          block_type,
          raw_text,
          normalized_text,
          table_json
        FROM doc_blocks
        WHERE section_title IS NOT NULL
          AND chapter_title IS NOT NULL
          AND section_title IN (${_placeholders(sectionTitles.length)})
          AND chapter_title IN (${_placeholders(chapterTitles.length)})
          AND block_id >= ?
        ORDER BY block_id
        ''',
        [
          ...sectionTitles,
          ...chapterTitles,
          minBlock,
        ],
      );

      final blockIds = rows
          .map<int>((row) => row['block_id'] as int)
          .toList(growable: false);
      final imageMap = await _loadImagesForBlocks(db, blockIds);

      return rows
          .map<DocBlock>(
            (row) => DocBlock(
              blockId: row['block_id'] as int,
              blockType: row['block_type'] as String? ?? 'text',
              rawText: _cleanBlockText(row['raw_text'] as String? ?? ''),
              normalizedText:
                  _cleanBlockText(row['normalized_text'] as String? ?? ''),
              tableJson: row['table_json'] as String?,
              imageBlobs: imageMap[row['block_id'] as int] ?? const [],
            ),
          )
          .toList();
    } catch (error) {
      debugPrint('SQL error in fetchChapterBlocks: $error');
      rethrow;
    }
  }

  Future<List<QuestionNavItem>> fetchQuestionIndex({
    required String sectionTitle,
    required String chapterTitle,
  }) async {
    final db = await database;
    final sectionTitles = await _resolveSectionTitles(db, sectionTitle);
    final chapterTitles =
        await _resolveChapterTitles(db, sectionTitles, chapterTitle);
    if (sectionTitles.isEmpty || chapterTitles.isEmpty) {
      return [];
    }
    final rows = await db.rawQuery(
      '''
      SELECT block_id, question_number, question_text
      FROM d_questions
      WHERE section_title IN (${_placeholders(sectionTitles.length)})
        AND chapter_title IN (${_placeholders(chapterTitles.length)})
      ORDER BY question_number
      ''',
      [
        ...sectionTitles,
        ...chapterTitles,
      ],
    );

    return rows
        .map<QuestionNavItem>(
          (row) => QuestionNavItem(
            blockId: row['block_id'] as int,
            questionNumber: row['question_number'] as int? ?? 0,
            questionText: _cleanBlockText(row['question_text'] as String? ?? ''),
          ),
        )
        .toList();
  }

  Future<ChapterEntry?> fetchPreviousChapter({
    required String sectionTitle,
    required String chapterTitle,
  }) async {
    final db = await database;
    final sectionTitles = await _resolveSectionTitles(db, sectionTitle);
    final chapterTitles =
        await _resolveChapterTitles(db, sectionTitles, chapterTitle);
    if (sectionTitles.isEmpty || chapterTitles.isEmpty) {
      return null;
    }
    final currentRows = await db.rawQuery(
      '''
      SELECT MIN(block_id) AS first_block
      FROM doc_blocks
      WHERE section_title IS NOT NULL
        AND chapter_title IS NOT NULL
        AND section_title IN (${_placeholders(sectionTitles.length)})
        AND chapter_title IN (${_placeholders(chapterTitles.length)})
      ''',
      [
        ...sectionTitles,
        ...chapterTitles,
      ],
    );
    final currentFirst = (currentRows.first['first_block'] as int?) ?? 0;
    if (currentFirst == 0) {
      return null;
    }

    final rows = await db.rawQuery(
      '''
      WITH chapters AS (
        SELECT section_title, chapter_title, MIN(block_id) AS first_block
        FROM doc_blocks
        WHERE section_title IS NOT NULL AND chapter_title IS NOT NULL
        GROUP BY section_title, chapter_title
      )
      SELECT section_title, chapter_title, first_block
      FROM chapters
      WHERE first_block < ?
      ORDER BY first_block DESC
      LIMIT 1
      ''',
      [currentFirst],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(row['section_title'] as String),
      chapterTitle: _stripTagPrefix(row['chapter_title'] as String),
      rawSectionTitle: row['section_title'] as String,
      rawChapterTitle: row['chapter_title'] as String,
      firstBlockId: row['first_block'] as int,
    );
  }

  Future<ChapterEntry?> fetchNextChapter({
    required String sectionTitle,
    required String chapterTitle,
  }) async {
    final db = await database;
    final sectionTitles = await _resolveSectionTitles(db, sectionTitle);
    final chapterTitles =
        await _resolveChapterTitles(db, sectionTitles, chapterTitle);
    if (sectionTitles.isEmpty || chapterTitles.isEmpty) {
      return null;
    }
    final currentRows = await db.rawQuery(
      '''
      SELECT MIN(block_id) AS first_block
      FROM doc_blocks
      WHERE section_title IS NOT NULL
        AND chapter_title IS NOT NULL
        AND section_title IN (${_placeholders(sectionTitles.length)})
        AND chapter_title IN (${_placeholders(chapterTitles.length)})
      ''',
      [
        ...sectionTitles,
        ...chapterTitles,
      ],
    );
    final currentFirst = (currentRows.first['first_block'] as int?) ?? 0;
    if (currentFirst == 0) {
      return null;
    }

    final rows = await db.rawQuery(
      '''
      WITH chapters AS (
        SELECT section_title, chapter_title, MIN(block_id) AS first_block
        FROM doc_blocks
        WHERE section_title IS NOT NULL AND chapter_title IS NOT NULL
        GROUP BY section_title, chapter_title
      )
      SELECT section_title, chapter_title, first_block
      FROM chapters
      WHERE first_block > ?
      ORDER BY first_block ASC
      LIMIT 1
      ''',
      [currentFirst],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return ChapterEntry(
      sectionTitle: _stripTagPrefix(row['section_title'] as String),
      chapterTitle: _stripTagPrefix(row['chapter_title'] as String),
      rawSectionTitle: row['section_title'] as String,
      rawChapterTitle: row['chapter_title'] as String,
      firstBlockId: row['first_block'] as int,
    );
  }

  Future<Map<int, List<Uint8List>>> _loadImagesForBlocks(
    Database db,
    List<int> blockIds,
  ) async {
    if (blockIds.isEmpty) {
      return {};
    }
    final placeholders = List.filled(blockIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT m.block_id, i.image_blob
      FROM brhc_image_block_map m
      JOIN brhc_images i ON i.image_id = m.image_id
      WHERE m.block_id IN ($placeholders)
      ORDER BY m.block_id, m.image_id
      ''',
      blockIds,
    );
    final imageMap = <int, List<Uint8List>>{};
    for (final row in rows) {
      final blockId = row['block_id'] as int;
      final blob = row['image_blob'] as Uint8List?;
      if (blob == null) {
        continue;
      }
      imageMap.putIfAbsent(blockId, () => []).add(blob);
    }
    return imageMap;
  }
}
