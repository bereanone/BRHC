import os
import shutil
import sqlite3
from collections import defaultdict

from dlbDocxClassify import INPUT_DOC, classify_docx

DB_PATH = "assets/databases/brhc.db"
TMP_PATH = f"{DB_PATH}.new"


def _load_table_schema(cur, table_name):
    cur.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        (table_name,),
    )
    row = cur.fetchone()
    if not row or not row[0]:
        raise RuntimeError(f"Missing schema for {table_name}")
    return row[0]


def _load_question_map(cur):
    cur.execute(
        "SELECT id, section_number, chapter_number, question_number FROM questions"
    )
    q_map = {}
    for row in cur.fetchall():
        q_map[(row[1], row[2], row[3])] = row[0]
    return q_map


def _load_image_map(cur):
    cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='brhc_images'"
    )
    if not cur.fetchone():
        return {}
    cur.execute("SELECT image_id, filename FROM brhc_images")
    return {row[1].strip().lower(): row[0] for row in cur.fetchall() if row[1]}


def _resolve_question_id(q_map, token):
    section = token.get("section") or 0
    chapter = token.get("chapter") or 0
    qnum = token.get("question")

    if qnum is not None:
        key = (section, chapter, qnum)
    else:
        key = (section, chapter, 0)

    if key not in q_map:
        raise RuntimeError(f"Missing question anchor for {key}")
    return q_map[key]


def _print_poetry_diagnostic(cur):
    row = cur.execute(
        "SELECT id FROM answer_blocks WHERE content LIKE ? ORDER BY id LIMIT 1",
        ("%Ps. 16:11%",),
    ).fetchone()
    if not row:
        print("Diagnostic: reference 'Ps. 16:11' not found")
        return
    start_id = row[0]
    rows = cur.execute(
        """
        SELECT id, block_type, content
        FROM answer_blocks
        WHERE id >= ?
        ORDER BY id
        LIMIT 20
        """,
        (start_id,),
    ).fetchall()
    print("Diagnostic: blocks after Ps. 16:11")
    for _, block_type, content in rows:
        preview = (content or "").replace("\n", " ")[:40]
        print(f"  {block_type}: {preview}")


def _validate_answer_blocks(db_path):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    print("=== BRHC VALIDATION REPORT ===")
    chapters = cur.execute(
        """
        SELECT DISTINCT chapter_number, chapter_title
        FROM questions
        WHERE chapter_number IS NOT NULL
        ORDER BY chapter_number
        """
    ).fetchall()
    for chapter_number, _ in chapters:
        issues = []
        info = []
        orphan_rows = cur.execute(
            """
            SELECT ab.id
            FROM answer_blocks ab
            JOIN questions q ON q.id = ab.question_id
            WHERE q.chapter_number = ? AND q.question_number = 0
            ORDER BY ab.id
            """,
            (chapter_number,),
        ).fetchall()
        for (block_id,) in orphan_rows:
            issues.append(f"  ❌ Orphan answer at block id {block_id}")

        empty_rows = cur.execute(
            """
            SELECT q.id
            FROM questions q
            LEFT JOIN answer_blocks ab ON ab.question_id = q.id
            WHERE q.chapter_number = ? AND q.question_number > 0
            GROUP BY q.id
            HAVING COUNT(ab.id) = 0
            ORDER BY q.sequence_in_chapter
            """,
            (chapter_number,),
        ).fetchall()
        for (question_id,) in empty_rows:
            issues.append(f"  ❌ Question id {question_id} has no answers")

        question_rows = cur.execute(
            """
            SELECT q.id
            FROM questions q
            WHERE q.chapter_number = ? AND q.question_number > 0
            ORDER BY q.sequence_in_chapter
            """,
            (chapter_number,),
        ).fetchall()
        for (question_id,) in question_rows:
            first = cur.execute(
                """
                SELECT block_type
                FROM answer_blocks
                WHERE question_id = ?
                ORDER BY block_order, id
                LIMIT 1
                """,
                (question_id,),
            ).fetchone()
            if first and first[0] == "poetry":
                info.append(
                    "  ℹ️ Poetry encountered before first answer "
                    f"(question id {question_id})"
                )

        print(f"Chapter {chapter_number}:")
        if issues or info:
            for line in issues:
                print(line)
            for line in info:
                print(line)
        else:
            print("  ✔ No issues found")

    conn.close()


def rebuild_database():
    if not os.path.exists(DB_PATH):
        raise RuntimeError(f"Database not found at {DB_PATH}")

    shutil.copyfile(DB_PATH, TMP_PATH)

    conn = sqlite3.connect(TMP_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()

    create_answer_blocks_sql = _load_table_schema(cur, "answer_blocks")
    q_map = _load_question_map(cur)
    img_map = _load_image_map(cur)

    tokens, _ = classify_docx(INPUT_DOC)

    try:
        conn.execute("BEGIN")
        cur.execute("DROP TABLE IF EXISTS answer_blocks")
        cur.execute(create_answer_blocks_sql)

        block_orders = defaultdict(int)
        next_block_id = 1

        for token in tokens:
            kind = token.get("kind")
            if kind in ("section_start", "chapter_start", "question"):
                continue

            meta = token.get("meta", {})
            block_type = meta.get("block_type", kind)
            if block_type == "question":
                raise RuntimeError("block_type='question' is not allowed in answer_blocks")

            question_id = _resolve_question_id(q_map, token)
            block_order = block_orders[question_id]
            block_orders[question_id] += 1

            text_value = token.get("text", "")
            if block_type in ("poetry", "responsive", "heading"):
                content = text_value
            else:
                content = text_value.strip()

            image_ref = None
            if block_type == "image":
                filename = meta.get("image_filename")
                if filename:
                    image_ref = img_map.get(filename.strip().lower())
                if image_ref is None:
                    raise RuntimeError(f"Missing image_ref for {filename}")

            cur.execute(
                """
                INSERT INTO answer_blocks (
                    id, question_id, block_order, block_type, content, reference, image_ref
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    next_block_id,
                    question_id,
                    block_order,
                    block_type,
                    content,
                    None,
                    image_ref,
                ),
            )
            next_block_id += 1

        conn.commit()
    except Exception:
        conn.rollback()
        conn.close()
        raise

    _print_poetry_diagnostic(cur)
    conn.close()

    os.replace(TMP_PATH, DB_PATH)


def main():
    rebuild_database()
    _validate_answer_blocks(DB_PATH)


if __name__ == "__main__":
    main()
