#!/usr/bin/env python3

import argparse
import json
import os
import re
import sqlite3
from datetime import datetime, timezone

from docx import Document
from docx.oxml.table import CT_Tbl
from docx.oxml.text.paragraph import CT_P
from docx.table import Table
from docx.text.paragraph import Paragraph

DB_PATH = "assets/databases/brhc.db"
DOCX_PATH = "docs/references/1914Tagged.docx"


def iter_block_items(doc):
    for child in doc.element.body.iterchildren():
        if isinstance(child, CT_P):
            yield Paragraph(child, doc)
        elif isinstance(child, CT_Tbl):
            yield Table(child, doc)


def word_count(text):
    if not text:
        return 0
    return len(text.split())


def normalize_question_text(text):
    if text is None:
        return ""
    stripped = re.sub(r"^\s*\d+[\.\)]\s*", "", text)
    stripped = re.sub(r"^\s*\d+\s+", "", stripped)
    return " ".join(stripped.split())


def normalize_text(text):
    if text is None:
        return ""
    normalized = text
    normalized = re.sub(r"Note:-\s*", "Note:- ", normalized)
    normalized = re.sub(r"Notes:-\s*", "Notes:- ", normalized)
    normalized = re.sub(r"(\w)[\r\n]+(\w)", r"\1 \2", normalized)
    normalized = normalize_book_names(normalized)
    normalized = " ".join(normalized.split())
    return normalized


def normalize_book_names(text):
    replacements = [
        (r"\bGen\.?(?=\s+\d)", "Genesis"),
        (r"\bEx\.?(?=\s+\d)", "Exodus"),
        (r"\bLev\.?(?=\s+\d)", "Leviticus"),
        (r"\bNum\.?(?=\s+\d)", "Numbers"),
        (r"\bDeut\.?(?=\s+\d)", "Deuteronomy"),
        (r"\bJosh\.?(?=\s+\d)", "Joshua"),
        (r"\bJudg\.?(?=\s+\d)", "Judges"),
        (r"\bRuth\.?(?=\s+\d)", "Ruth"),
        (r"\b1\s*Sam\.?(?=\s+\d)", "1 Samuel"),
        (r"\b2\s*Sam\.?(?=\s+\d)", "2 Samuel"),
        (r"\b1\s*Kgs\.?(?=\s+\d)", "1 Kings"),
        (r"\b2\s*Kgs\.?(?=\s+\d)", "2 Kings"),
        (r"\b1\s*Chron\.?(?=\s+\d)", "1 Chronicles"),
        (r"\b2\s*Chron\.?(?=\s+\d)", "2 Chronicles"),
        (r"\bEzra\.?(?=\s+\d)", "Ezra"),
        (r"\bNeh\.?(?=\s+\d)", "Nehemiah"),
        (r"\bEsth\.?(?=\s+\d)", "Esther"),
        (r"\bJob\.?(?=\s+\d)", "Job"),
        (r"\bPs\.?(?=\s+\d)", "Psalms"),
        (r"\bProv\.?(?=\s+\d)", "Proverbs"),
        (r"\bEccl\.?(?=\s+\d)", "Ecclesiastes"),
        (r"\bSong\.?(?=\s+\d)", "Song of Solomon"),
        (r"\bIsa\.?(?=\s+\d)", "Isaiah"),
        (r"\bJer\.?(?=\s+\d)", "Jeremiah"),
        (r"\bLam\.?(?=\s+\d)", "Lamentations"),
        (r"\bEzek\.?(?=\s+\d)", "Ezekiel"),
        (r"\bDan\.?(?=\s+\d)", "Daniel"),
        (r"\bHos\.?(?=\s+\d)", "Hosea"),
        (r"\bJoel\.?(?=\s+\d)", "Joel"),
        (r"\bAmos\.?(?=\s+\d)", "Amos"),
        (r"\bObad\.?(?=\s+\d)", "Obadiah"),
        (r"\bJonah\.?(?=\s+\d)", "Jonah"),
        (r"\bMic\.?(?=\s+\d)", "Micah"),
        (r"\bNah\.?(?=\s+\d)", "Nahum"),
        (r"\bHab\.?(?=\s+\d)", "Habakkuk"),
        (r"\bZeph\.?(?=\s+\d)", "Zephaniah"),
        (r"\bHag\.?(?=\s+\d)", "Haggai"),
        (r"\bZech\.?(?=\s+\d)", "Zechariah"),
        (r"\bMal\.?(?=\s+\d)", "Malachi"),
        (r"\bMatt\.?(?=\s+\d)", "Matthew"),
        (r"\bMark\.?(?=\s+\d)", "Mark"),
        (r"\bLuke\.?(?=\s+\d)", "Luke"),
        (r"\bJohn\.?(?=\s+\d)", "John"),
        (r"\bActs\.?(?=\s+\d)", "Acts"),
        (r"\bRom\.?(?=\s+\d)", "Romans"),
        (r"\b1\s*Cor\.?(?=\s+\d)", "1 Corinthians"),
        (r"\b2\s*Cor\.?(?=\s+\d)", "2 Corinthians"),
        (r"\bGal\.?(?=\s+\d)", "Galatians"),
        (r"\bEph\.?(?=\s+\d)", "Ephesians"),
        (r"\bPhil\.?(?=\s+\d)", "Philippians"),
        (r"\bCol\.?(?=\s+\d)", "Colossians"),
        (r"\b1\s*Thess\.?(?=\s+\d)", "1 Thessalonians"),
        (r"\b2\s*Thess\.?(?=\s+\d)", "2 Thessalonians"),
        (r"\b1\s*Tim\.?(?=\s+\d)", "1 Timothy"),
        (r"\b2\s*Tim\.?(?=\s+\d)", "2 Timothy"),
        (r"\bTitus\.?(?=\s+\d)", "Titus"),
        (r"\bPhilem\.?(?=\s+\d)", "Philemon"),
        (r"\bHeb\.?(?=\s+\d)", "Hebrews"),
        (r"\bJas\.?(?=\s+\d)", "James"),
        (r"\b1\s*Pet\.?(?=\s+\d)", "1 Peter"),
        (r"\b2\s*Pet\.?(?=\s+\d)", "2 Peter"),
        (r"\b1\s*John\.?(?=\s+\d)", "1 John"),
        (r"\b2\s*John\.?(?=\s+\d)", "2 John"),
        (r"\b3\s*John\.?(?=\s+\d)", "3 John"),
        (r"\bJude\.?(?=\s+\d)", "Jude"),
        (r"\bRev\.?(?=\s+\d)", "Revelation"),
    ]
    normalized = text
    for pattern, replacement in replacements:
        normalized = re.sub(pattern, replacement, normalized)
    return normalized


def is_blue(run):
    if not run.font.color or not run.font.color.rgb:
        return False
    r, g, b = run.font.color.rgb
    return r == 0 and g == 0 and b >= 0x80


def is_black(run):
    if not run.font.color or not run.font.color.rgb:
        return True
    r, g, b = run.font.color.rgb
    return r == 0 and g == 0 and b == 0


def is_page_number(p):
    text = (p.text or "").strip()
    if not re.match(r"^Page\s+\d+$", text, re.IGNORECASE):
        return False
    has_run = False
    for r in p.runs:
        has_run = True
        if not r.bold or not is_black(r):
            return False
    return has_run


def table_to_json(table):
    rows = []
    for row in table.rows:
        row_data = []
        for cell in row.cells:
            cell_lines = []
            for p in cell.paragraphs:
                cell_lines.append(p.text)
            row_data.append(cell_lines)
        rows.append(row_data)
    return rows


def strip_tag(text, tag):
    if text is None:
        return ""
    return text.replace(tag, "", 1).strip()


def init_schema(cur):
    # Canonical schemas for this project
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS brhc_images(
          image_id INTEGER PRIMARY KEY AUTOINCREMENT,
          image_blob BLOB NOT NULL
        );

        CREATE TABLE IF NOT EXISTS brhc_image_block_map(
          image_id INTEGER NOT NULL,
          block_id INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS d_questions(
          question_id INTEGER PRIMARY KEY AUTOINCREMENT,
          block_id INTEGER NOT NULL,
          question_number INTEGER,
          question_text TEXT NOT NULL,
          section_title TEXT,
          chapter_title TEXT
        );
        """
    )

    # --- doc_blocks migration if needed ---
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='doc_blocks'")
    exists = cur.fetchone() is not None

    if not exists:
        cur.execute(
            """
            CREATE TABLE doc_blocks (
              block_id INTEGER PRIMARY KEY,
              section_title TEXT,
              chapter_title TEXT,
              block_order INTEGER NOT NULL,
              block_type TEXT NOT NULL,
              raw_text TEXT,
              normalized_text TEXT,
              table_json TEXT,
              image_blob_id INTEGER
            )
            """
        )
        return

    # If it exists, inspect columns
    cols = [r[1] for r in cur.execute("PRAGMA table_info(doc_blocks)").fetchall()]
    needs_migration = ("raw_text" not in cols) or ("normalized_text" not in cols)

    if needs_migration:
        # Create new canonical table
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS doc_blocks_new (
              block_id INTEGER PRIMARY KEY,
              section_title TEXT,
              chapter_title TEXT,
              block_order INTEGER NOT NULL,
              block_type TEXT NOT NULL,
              raw_text TEXT,
              normalized_text TEXT,
              table_json TEXT,
              image_blob_id INTEGER
            )
            """
        )

        # Map old columns if they exist
        # Old schema seen: (block_id, section_title, chapter_title, block_order, block_type, text_content, table_json, image_blob_id)
        has_text_content = "text_content" in cols
        has_table_json = "table_json" in cols
        has_image_blob_id = "image_blob_id" in cols

        if has_text_content:
            insert_sql = """
                INSERT INTO doc_blocks_new(
                  block_id, section_title, chapter_title, block_order, block_type,
                  raw_text, normalized_text, table_json, image_blob_id
                )
                SELECT
                  block_id,
                  section_title,
                  chapter_title,
                  COALESCE(block_order, block_id),
                  COALESCE(block_type, 'text'),
                  text_content,
                  text_content,
                  {table_json_sel},
                  {image_sel}
                FROM doc_blocks
            """
            table_json_sel = "table_json" if has_table_json else "NULL"
            image_sel = "image_blob_id" if has_image_blob_id else "NULL"
            cur.execute(insert_sql.format(table_json_sel=table_json_sel, image_sel=image_sel))
        else:
            # Best-effort copy of shared columns
            shared = [c for c in ["block_id","section_title","chapter_title","block_order","block_type","table_json","image_blob_id"] if c in cols]
            select_list = ", ".join(shared) if shared else "block_id"
            # Fill required columns with defaults
            cur.execute(
                f"""
                INSERT INTO doc_blocks_new(
                  block_id, section_title, chapter_title, block_order, block_type,
                  raw_text, normalized_text, table_json, image_blob_id
                )
                SELECT
                  block_id,
                  {('section_title' if 'section_title' in cols else 'NULL')},
                  {('chapter_title' if 'chapter_title' in cols else 'NULL')},
                  {('COALESCE(block_order, block_id)' if 'block_order' in cols else 'block_id')},
                  {("COALESCE(block_type, 'text')" if 'block_type' in cols else "'text'")},
                  NULL,
                  NULL,
                  {('table_json' if 'table_json' in cols else 'NULL')},
                  {('image_blob_id' if 'image_blob_id' in cols else 'NULL')}
                FROM doc_blocks
                """
            )

        # Swap tables
        cur.execute("DROP TABLE doc_blocks")
        cur.execute("ALTER TABLE doc_blocks_new RENAME TO doc_blocks")

    # --- d_questions migration if needed ---
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='d_questions'")
    if cur.fetchone() is not None:
        dq_cols = [r[1] for r in cur.execute("PRAGMA table_info(d_questions)").fetchall()]
        if "block_id" not in dq_cols:
            cur.execute("ALTER TABLE d_questions ADD COLUMN block_id INTEGER")
        if "question_number" not in dq_cols:
            cur.execute("ALTER TABLE d_questions ADD COLUMN question_number INTEGER")
        if "question_text" not in dq_cols:
            cur.execute("ALTER TABLE d_questions ADD COLUMN question_text TEXT")
        if "section_title" not in dq_cols:
            cur.execute("ALTER TABLE d_questions ADD COLUMN section_title TEXT")
        if "chapter_title" not in dq_cols:
            cur.execute("ALTER TABLE d_questions ADD COLUMN chapter_title TEXT")

    # Ensure indices helpful for ordering
    cur.execute("CREATE INDEX IF NOT EXISTS idx_doc_blocks_order ON doc_blocks(section_title, chapter_title, block_order, block_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_doc_blocks_type ON doc_blocks(block_type)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_d_questions_block ON d_questions(block_id)")


def import_docx(cur):
    if not os.path.exists(DOCX_PATH):
        raise SystemExit(f"DOCX not found: {DOCX_PATH}")

    doc = Document(DOCX_PATH)
    cur.execute("DELETE FROM doc_blocks;")
    cur.execute("DELETE FROM d_questions;")
    # NOTE: Leaving existing image blobs intact by default.
    # If you want a full rebuild, uncomment the next two lines.
    # cur.execute("DELETE FROM brhc_images;")
    # cur.execute("DELETE FROM brhc_image_block_map;")

    section_title = None
    chapter_title = None
    question_counters = {}
    question_counts = {}
    block_id = 0
    sections = set()
    chapters = set()
    images_inserted = 0

    for item in iter_block_items(doc):
        if isinstance(item, Paragraph):
            text = item.text or ""
            stripped = text.strip()
            if not stripped:
                continue
            if is_page_number(item):
                continue

            if item.style and item.style.name == "Heading 2":
                section_title = stripped
                sections.add(section_title)
                continue

            if item.style and item.style.name == "Heading 3" and stripped.startswith("[Ch]"):
                chapter_title = strip_tag(stripped, "[Ch]")
                chapters.add((section_title, chapter_title))
                question_counters[(section_title, chapter_title)] = 0
                question_counts[(section_title, chapter_title)] = 0
                continue

            block_type = "text"
            raw_text = stripped

            if stripped.startswith("[N]"):
                block_type = "note"
                raw_text = strip_tag(stripped, "[N]")
            elif stripped.startswith("[P]"):
                block_type = "poetry"
                raw_text = strip_tag(stripped, "[P]")
            elif stripped.startswith("[T]"):
                block_type = "table"
                raw_text = strip_tag(stripped, "[T]")
            elif stripped.startswith("[R]"):
                block_type = "reading"
                raw_text = strip_tag(stripped, "[R]")
            elif any(is_blue(r) for r in item.runs):
                # Questions are blue in this tagged DOCX. Some are numbered, some are not.
                # Most end with '?', but we also accept lines that start with a number.
                if stripped.endswith("?") or re.match(r"^\s*\d{1,3}[\.)]?\s+", stripped):
                    block_type = "question"
                    raw_text = stripped
                else:
                    # Blue but not a question — treat as regular text so we don't lose it
                    block_type = "text"
                    raw_text = stripped

            normalized = normalize_text(raw_text)
            block_id += 1

            cur.execute(
                """
                INSERT INTO doc_blocks(
                  block_id,
                  section_title,
                  chapter_title,
                  block_order,
                  block_type,
                  raw_text,
                  normalized_text,
                  table_json,
                  image_blob_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    block_id,
                    section_title,
                    chapter_title,
                    block_id,
                    block_type,
                    raw_text,
                    normalized,
                    None,
                    None,
                ),
            )

            if block_type == "question":
                key = (section_title, chapter_title)
                question_counters[key] = question_counters.get(key, 0) + 1
                question_number = question_counters[key]
                question_counts[key] = question_counts.get(key, 0) + 1
                question_text = normalize_question_text(raw_text)
                cur.execute(
                    """
                    INSERT INTO d_questions(
                      section_title,
                      chapter_title,
                      question_number,
                      question_text,
                      block_id
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (section_title, chapter_title, question_number, question_text, block_id),
                )

            for run in item.runs:
                image_ids = extract_images_from_run(run)
                for image_blob in image_ids:
                    cur.execute(
                        "INSERT INTO brhc_images(image_blob) VALUES (?);",
                        (image_blob,),
                    )
                    image_id = cur.lastrowid
                    cur.execute(
                        "INSERT INTO brhc_image_block_map(image_id, block_id) VALUES (?, ?);",
                        (image_id, block_id),
                    )
                    images_inserted += 1

        elif isinstance(item, Table):
            block_id += 1
            table_json = json.dumps(table_to_json(item), ensure_ascii=True)
            cur.execute(
                """
                INSERT INTO doc_blocks(
                  block_id,
                  section_title,
                  chapter_title,
                  block_order,
                  block_type,
                  raw_text,
                  normalized_text,
                  table_json,
                  image_blob_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    block_id,
                    section_title,
                    chapter_title,
                    block_id,
                    "table",
                    "",
                    "",
                    table_json,
                    None,
                ),
            )

    # Deterministic rebuild of d_questions from doc_blocks
    total_questions = rebuild_d_questions_from_blocks(cur)

    return {
        "sections": len(sections),
        "chapters": len(chapters),
        "total_questions": total_questions,
        "questions_per_chapter": question_counts,
    }


def extract_images_from_run(run):
    image_blobs = []
    for el in run._element.iter():
        if el.tag == "{http://schemas.openxmlformats.org/drawingml/2006/main}blip":
            rid = el.get(
                "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed"
            )
            if rid:
                image_part = run.part.related_parts.get(rid)
                if image_part:
                    image_blobs.append(image_part.blob)
    return image_blobs


def rebuild_d_questions_from_blocks(cur):
    cur.execute("DELETE FROM d_questions")

    # Order chapters by first block_id encountered
    chapters = cur.execute(
        """
        SELECT section_title, chapter_title, MIN(block_id) AS first_block
        FROM doc_blocks
        WHERE chapter_title IS NOT NULL AND chapter_title <> ''
        GROUP BY section_title, chapter_title
        ORDER BY first_block
        """
    ).fetchall()

    total = 0
    for section_title, chapter_title, _first in chapters:
        qnum = 0
        rows = cur.execute(
            """
            SELECT block_id, raw_text
            FROM doc_blocks
            WHERE section_title IS ? AND chapter_title IS ? AND block_type='question'
            ORDER BY block_id
            """,
            (section_title, chapter_title),
        ).fetchall()

        for block_id, raw_text in rows:
            qnum += 1
            qtext = normalize_question_text(raw_text)
            cur.execute(
                """
                INSERT INTO d_questions(block_id, question_number, question_text, section_title, chapter_title)
                VALUES (?, ?, ?, ?, ?)
                """,
                (block_id, qnum, qtext, section_title, chapter_title),
            )
            total += 1

    return total


def verify(cur):
    dq_cols = [r[1] for r in cur.execute("PRAGMA table_info(d_questions)").fetchall()]
    if "section_title" not in dq_cols or "chapter_title" not in dq_cols:
        print("d_questions schema is missing section_title/chapter_title. Run --init-schema first.")
        return
    cur.execute(
        """
        SELECT section_title, chapter_title, COUNT(*) as count
        FROM d_questions
        GROUP BY section_title, chapter_title
        ORDER BY section_title, chapter_title
        """
    )
    rows = cur.fetchall()
    total = 0
    for section_title, chapter_title, count in rows:
        total += count
        print(f"{section_title} | {chapter_title}: {count}")
    print(f"Total questions: {total}")

    cur.execute("SELECT block_type, COUNT(*) FROM doc_blocks GROUP BY block_type ORDER BY COUNT(*) DESC")
    for bt, n in cur.fetchall():
        print(f"Blocks[{bt}]: {n}")


def main():
    parser = argparse.ArgumentParser(description="BRHC DOCX import and normalization.")
    parser.add_argument("--init-schema", action="store_true", help="Create or verify schema.")
    parser.add_argument("--import-docx", action="store_true", help="Import DOCX into SQLite.")
    parser.add_argument("--verify", action="store_true", help="Verify counts.")
    args = parser.parse_args()

    if not os.path.exists(DB_PATH):
        raise SystemExit(f"Database not found: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
    conn.execute("PRAGMA busy_timeout=30000;")
    cur = conn.cursor()

    if args.init_schema:
        conn.execute("BEGIN")
        init_schema(cur)
        conn.commit()

    if args.import_docx:
        conn.execute("BEGIN")
        init_schema(cur)
        result = import_docx(cur)
        conn.commit()
        print(f"Sections: {result['sections']}")
        print(f"Chapters: {result['chapters']}")
        for key, count in result["questions_per_chapter"].items():
            print(f"{key[0]} | {key[1]}: {count}")
        print(f"Total questions: {result['total_questions']}")

    if args.verify:
        verify(cur)

    conn.close()


if __name__ == "__main__":
    main()
