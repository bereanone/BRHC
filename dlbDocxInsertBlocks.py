import os
import re
import sqlite3
from collections import defaultdict

from dlbDocxClassify import classify_docx, INPUT_DOC

DB_PATH = "assets/databases/brhc.db"


def _load_question_map(cur):
    cur.execute(
        "SELECT id, chapter_id, question_number FROM questions"
    )
    q_map = {}
    for row in cur.fetchall():
        q_map[(row[1], row[2])] = row[0]
    return q_map


def _load_image_filenames(cur):
    cur.execute("SELECT filename FROM images")
    return {row[0].strip().lower() for row in cur.fetchall() if row[0]}


def _resolve_question_id(q_map, token):
    chapter = token.get("chapter_id") or token.get("chapter") or 0
    qnum = token.get("question")

    if qnum is not None:
        key = (chapter, qnum)
    else:
        key = (chapter, 0)

    return q_map.get(key)


def _strip_tag_prefix(text):
    return re.sub(r"^\s*\[[A-Za-z]+\]\s*", "", text or "").strip()


def _ensure_anchor_question(cur, section, chapter, qnum):
    cur.execute(
        """
        SELECT id FROM questions
        WHERE section_number=? AND chapter_number=? AND question_number=?
        """,
        (section, chapter, qnum),
    )
    row = cur.fetchone()
    if row:
        return row[0]

    cur.execute(
        """
        INSERT INTO questions (
            section_number,
            chapter_number,
            question_number,
            sequence_in_book,
            sequence_in_chapter,
            section_title,
            chapter_title,
            question_text
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (section, chapter, qnum, 0, 0, "", "", "[ANCHOR]"),
    )
    return cur.lastrowid


def insert_blocks(tokens, db_path=DB_PATH):
    if not os.path.exists(db_path):
        raise RuntimeError(f"Database not found at {db_path}")

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    stats = {
        "inserted": 0,
        "global_intro": 0,
        "section_intro": 0,
        "responsive": 0,
    }

    img_filenames = _load_image_filenames(cur)

    cur.execute("DELETE FROM questions")
    cur.execute("DELETE FROM chapters")

    cur.execute("DELETE FROM answer_blocks")

    block_orders = defaultdict(int)
    question_orders = defaultdict(int)
    chapter_titles = {}
    current_section = 0
    current_section_title = ""

    for token in tokens:
        kind = token.get("kind")
        if kind == "section_start":
            current_section = token.get("section") or 0
            current_section_title = _strip_tag_prefix(token.get("text", ""))
            continue
        if kind == "chapter_start":
            chapter_id = token.get("chapter_id") or 0
            if chapter_id not in chapter_titles:
                chapter_titles[chapter_id] = _strip_tag_prefix(token.get("text", ""))
            continue
        if kind == "question":
            chapter_id = token.get("chapter_id") or 0
            qnum = token.get("question")
            if qnum is None:
                continue
            order_in_chapter = question_orders[chapter_id]
            question_orders[chapter_id] += 1
            cur.execute(
                """
                INSERT INTO questions (
                    chapter_id,
                    order_in_chapter,
                    question_number,
                    question_text,
                    section_number,
                    section_title
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    chapter_id,
                    order_in_chapter,
                    qnum,
                    token.get("text", ""),
                    current_section,
                    current_section_title,
                ),
            )

    for chapter_id in sorted(chapter_titles.keys()):
        cur.execute(
            "INSERT INTO chapters (chapter_id, chapter_title) VALUES (?, ?)",
            (chapter_id, chapter_titles[chapter_id]),
        )

    q_map = _load_question_map(cur)

    for token in tokens:
        kind = token.get("kind")
        if kind in ("section_start", "chapter_start", "question", "section_intro"):
            continue

        meta = token.get("meta", {})
        block_type = meta.get("block_type", kind)
        if block_type == "question":
            raise RuntimeError("block_type='question' is not allowed in answer_blocks")

        chapter_id = token.get("chapter_id")
        if chapter_id is None:
            chapter_id = token.get("chapter") or 0
        question_id = None
        if kind == "question" or (kind == "answer" and token.get("question") is not None):
            question_id = _resolve_question_id(q_map, token)

        block_order = block_orders[chapter_id]
        block_orders[chapter_id] += 1

        text_value = token.get("text", "")
        # Preserve poetry line structure; do not strip or normalize
        if block_type in ("poetry", "responsive", "heading"):
            content = text_value
        else:
            content = text_value.strip()
        image_ref = None
        if block_type == "image":
            filename = token.get("meta", {}).get("image_filename")
            if filename:
                image_ref = filename.strip()
                if image_ref.lower() not in img_filenames:
                    raise RuntimeError(f"Missing image_ref for {filename}")
            else:
                raise RuntimeError("Missing image_ref for image block")

        cur.execute(
            """
            INSERT INTO answer_blocks (
                chapter_id, question_id, block_order, block_type, content, reference, image_ref
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (chapter_id, question_id, block_order, block_type, content, None, image_ref),
        )

        stats["inserted"] += 1
        if kind == "global_intro":
            stats["global_intro"] += 1
        elif kind == "section_intro":
            stats["section_intro"] += 1
        elif kind == "responsive":
            stats["responsive"] += 1

    conn.commit()

    cur.execute("SELECT COUNT(*) FROM answer_blocks WHERE chapter_id IS NULL")
    if cur.fetchone()[0] != 0:
        raise RuntimeError("Post-import validation failed: NULL chapter_id found")
    cur.execute("SELECT COUNT(*) FROM questions")
    if cur.fetchone()[0] == 0:
        raise RuntimeError("Post-import validation failed: questions table is empty")
    cur.execute("SELECT COUNT(*) FROM chapters")
    if cur.fetchone()[0] == 0:
        raise RuntimeError("Post-import validation failed: chapters table is empty")

    print(f"Total blocks inserted: {stats['inserted']}")
    print(f"Global intro blocks: {stats['global_intro']}")
    print(f"Section intro blocks: {stats['section_intro']}")
    print(f"Responsive reading count: {stats['responsive']}")

    conn.close()


def main():
    tokens, _ = classify_docx(INPUT_DOC)
    insert_blocks(tokens, DB_PATH)


if __name__ == "__main__":
    main()
