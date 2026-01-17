import os
import sqlite3
from collections import defaultdict

from dlbDocxClassify import classify_docx, INPUT_DOC

DB_PATH = "assets/databases/brhc.db"


def _load_question_map(cur):
    cur.execute(
        "SELECT id, section_number, chapter_number, question_number FROM questions"
    )
    q_map = {}
    for row in cur.fetchall():
        q_map[(row[1], row[2], row[3])] = row[0]
    return q_map


def _load_image_map(cur):
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='brhc_images'")
    if not cur.fetchone():
        return {}
    cur.execute("SELECT image_id, filename FROM brhc_images")
    return {row[1].strip().lower(): row[0] for row in cur.fetchall() if row[1]}


def _resolve_question_id(q_map, token):
    kind = token.get("kind")
    section = token.get("section") or 0
    chapter = token.get("chapter") or 0
    qnum = token.get("question")

    if kind == "global_intro":
        key = (0, 0, 0)
    elif kind == "section_intro":
        key = (section, 0, 0)
    elif qnum is not None:
        key = (section, chapter, qnum)
    else:
        key = (section, chapter, 0)

    if key not in q_map:
        raise RuntimeError(f"Missing question anchor for {key}")
    return q_map[key]


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

    q_map = _load_question_map(cur)

    # Ensure global intro anchor
    _ensure_anchor_question(cur, 0, 0, 0)

    # Ensure section and chapter intro anchors
    for token in tokens:
        if token.get("kind") == "section_start":
            sec = token.get("section") or 0
            _ensure_anchor_question(cur, sec, 0, 0)
        elif token.get("kind") == "chapter_start":
            sec = token.get("section") or 0
            chap = token.get("chapter") or 0
            _ensure_anchor_question(cur, sec, chap, 0)

    conn.commit()
    q_map = _load_question_map(cur)

    img_map = _load_image_map(cur)

    cur.execute("DELETE FROM answer_blocks")

    block_orders = defaultdict(int)

    for token in tokens:
        kind = token.get("kind")
        if kind in ("section_start", "chapter_start", "question", "section_intro"):
            continue

        meta = token.get("meta", {})
        block_type = meta.get("block_type", kind)
        if block_type == "question":
            raise RuntimeError("block_type='question' is not allowed in answer_blocks")

        if kind == "responsive":
            token = dict(token)
            token["question"] = None

        question_id = _resolve_question_id(q_map, token)
        block_order = block_orders[question_id]
        block_orders[question_id] += 1

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
                image_ref = img_map.get(filename.strip().lower())
            if image_ref is None:
                raise RuntimeError(f"Missing image_ref for {filename}")

        cur.execute(
            """
            INSERT INTO answer_blocks (
                question_id, block_order, block_type, content, reference, image_ref
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (question_id, block_order, block_type, content, None, image_ref),
        )

        stats["inserted"] += 1
        if kind == "global_intro":
            stats["global_intro"] += 1
        elif kind == "section_intro":
            stats["section_intro"] += 1
        elif kind == "responsive":
            stats["responsive"] += 1

    conn.commit()

    cur.execute("SELECT COUNT(*) FROM answer_blocks WHERE question_id IS NULL")
    if cur.fetchone()[0] != 0:
        raise RuntimeError("Post-import validation failed: NULL question_id found")

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
