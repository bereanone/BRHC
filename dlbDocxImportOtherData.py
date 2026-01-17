import sqlite3
import re
import os
from docx import Document
from dlbDocxClassify import classify_docx
from dlbDocxInsertBlocks import insert_blocks

INPUT_DOC = "docs/references/BRHC1914-Qmarked.docx"
DB_PATH = "assets/databases/brhc.db"

# Regex
SECTION_RE = re.compile(r"Section\s+(\d+)", re.IGNORECASE)
CHAPTER_RE = re.compile(r"Chapter\s+(\d+)", re.IGNORECASE)
PIC_RE = re.compile(r"\[Pic:\s*([^\]]+)\]", re.IGNORECASE)
QNUM_START_RE = re.compile(r"^\s*(\d{1,3})\s*\.")
RESPONSIVE_RE = re.compile(r"\bRESPONSIVE\s+READING\b", re.IGNORECASE)

def _rgb_tuple(rgb):
    if rgb is None:
        return None
    try:
        return (int(rgb[0]), int(rgb[1]), int(rgb[2]))
    except Exception:
        return None

def _is_redish(rgb):
    t = _rgb_tuple(rgb)
    if not t:
        return False
    r, g, b = t
    return r >= 150 and r > g + 40 and r > b + 40

def _is_blueish(rgb):
    t = _rgb_tuple(rgb)
    if not t:
        return False
    r, g, b = t
    return b >= 150 and b > g + 30 and b > r + 30

def _extract_leading_qnum(text):
    m = QNUM_START_RE.match(text)
    if m:
        return int(m.group(1))
    return None

def main():
    if not os.path.exists(INPUT_DOC):
        print(f"Error: Input document not found at {INPUT_DOC}")
        return
    if not os.path.exists(DB_PATH):
        print(f"Error: Database not found at {DB_PATH}")
        return
    tokens, _ = classify_docx(INPUT_DOC)
    insert_blocks(tokens, DB_PATH)
    return

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    stats = {
        "inserted": 0,
        "with_q_id": 0,
        "without_q_id": 0,
        "notes": 0,
        "poetry": 0,
        "responsive": 0,
        "images": 0
    }

    debug = os.environ.get("BRHC_TRACE", "").strip() == "1"

    # 1. Load Questions Map
    cur.execute("SELECT id, section_number, chapter_number, question_number FROM questions")
    q_map = {}
    for row in cur.fetchall():
        key = (row[1], row[2], row[3])
        q_map[key] = row[0]

    # Load Section Titles Map
    cur.execute("SELECT section_id, section_title FROM brhc_sections")
    section_title_map = {row[0]: row[1] for row in cur.fetchall()}

    # 2. Load Images Map
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='brhc_images'")
    if cur.fetchone():
        cur.execute("SELECT image_id, filename FROM brhc_images")
        img_map = {row[1].strip().lower(): row[0] for row in cur.fetchall() if row[1]}
    else:
        img_map = {}

    # 3. Clear Target Table
    cur.execute("DELETE FROM answer_blocks")

    # 4. Process Document
    doc = Document(INPUT_DOC)

    current_section = 0
    current_chapter = 0
    current_q_id = None
    first_q_id_in_chapter = None
    block_order = 0
    # True until we encounter the first [S] section marker
    in_global_intro = True
    # --- Global Introduction Anchor Setup ---
    # Ensure global introduction anchor exists (section=0, chapter=0, question=0)
    cur.execute("""
        SELECT id FROM questions
        WHERE section_number=0 AND chapter_number=0 AND question_number=0
    """)
    row = cur.fetchone()
    if row:
        global_intro_q_id = row[0]
    else:
        cur.execute("""
            INSERT INTO questions (
                section_number,
                section_title,
                chapter_number,
                chapter_title,
                question_number,
                sequence_in_book,
                sequence_in_chapter,
                question_text
            ) VALUES (?, ?, 0, 'Introduction', 0, 0, 0, '[ANCHOR]')
        """, (0, 'Introduction'))
        global_intro_q_id = cur.lastrowid
    global_intro_block_order = 0

    for para in doc.paragraphs:
        text = para.text
        text_stripped = text.strip()
        if not text_stripped:
            continue

        # Structural Markers must be processed BEFORE any global-intro handling
        if text_stripped.startswith("[S]"):
            m = SECTION_RE.search(text_stripped)
            current_section = int(m.group(1)) if m else 0
            current_chapter = 0
            block_order = 0
            current_q_id = None
            first_q_id_in_chapter = None
            continue

        if text_stripped.startswith("[Ch]"):
            in_global_intro = False
            m = CHAPTER_RE.search(text_stripped)
            current_chapter = int(m.group(1)) if m else 0
            block_order = 0
            current_q_id = None
            first_q_id_in_chapter = None
            if current_chapter == 0:
                continue

            # Fetch section title (required)
            section_title = section_title_map.get(current_section)
            if section_title is None:
                raise RuntimeError(f"Missing section_title for section {current_section}")

            # Ensure chapter anchor exists (question_number = 0)
            cur.execute("""
                SELECT id FROM questions
                WHERE section_number=? AND chapter_number=? AND question_number=0
            """, (current_section, current_chapter))
            row = cur.fetchone()

            if row:
                anchor_q_id = row[0]
            else:
                cur.execute("""
                    INSERT INTO questions (
                        section_number,
                        section_title,
                        chapter_number,
                        chapter_title,
                        question_number,
                        sequence_in_book,
                        sequence_in_chapter,
                        question_text
                    ) VALUES (?, ?, ?, ?, 0, ?, 0, '[ANCHOR]')
                """, (
                    current_section,
                    section_title,
                    current_chapter,
                    f'Chapter {current_chapter}',
                    current_chapter
                ))
                anchor_q_id = cur.lastrowid

            current_q_id = anchor_q_id
            first_q_id_in_chapter = anchor_q_id
            if debug:
                print(f"[TRACE] Chapter {current_chapter} anchor q_id={anchor_q_id}")
            continue

        # --- Global Introduction Handling ---
        # Before the first [S] Section marker, treat every non-empty paragraph as a global intro block.
        if in_global_intro:
            block_type = "answer"
            content = text
            image_ref = None

            if text_stripped.startswith("[P]"):
                block_type = "poetry"
                content = text_stripped[3:].lstrip()
                stats["poetry"] += 1
            elif text_stripped.startswith("[N]"):
                block_type = "note"
                content = text[3:].strip()
                stats["notes"] += 1
            elif text_stripped.startswith("[Pic:"):
                m = PIC_RE.match(text_stripped)
                if m:
                    fname = m.group(1).strip()
                    fname_lower = fname.lower()
                    block_type = "image"
                    content = f"[Pic:{fname}]"
                    image_ref = img_map.get(fname_lower)
                    stats["images"] += 1

            cur.execute("""
                INSERT INTO answer_blocks (
                    question_id, block_order, block_type, content, reference, image_ref
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (global_intro_q_id, global_intro_block_order, block_type, content, None, image_ref))

            stats["inserted"] += 1
            stats["with_q_id"] += 1
            global_intro_block_order += 1
            continue

        # Sections are metadata only — no section intro blocks allowed
        if current_chapter == 0:
            if debug:
                print(f"[TRACE] Skipping section-level content | section={current_section} text='{text_stripped[:80]}'")
            continue

        # Structural Markers (duplicate block removed)

        # Question Detection
        has_blue = False
        red_digits = []
        
        for run in para.runs:
            if not run.text:
                continue
            rgb = run.font.color.rgb if run.font.color else None
            if _is_blueish(rgb):
                has_blue = True
            if _is_redish(rgb):
                for char in run.text:
                    if char.isdigit():
                        red_digits.append(char)
        
        normalized = " ".join(text.split())
        upper = normalized.upper()

        # Responsive reading detection moved here
        if text_stripped.startswith("[R]") or RESPONSIVE_RE.search(text_stripped):
            if debug:
                print(f"[TRACE] Responsive detected | section={current_section} chapter={current_chapter} text='{text_stripped}'")
            # Responsive readings ALWAYS belong to the chapter anchor (question_number = 0)
            cur.execute("""
                SELECT id FROM questions
                WHERE section_number=? AND chapter_number=? AND question_number=0
            """, (current_section, current_chapter))
            row = cur.fetchone()
            if not row:
                raise RuntimeError("Invariant violated: responsive reading without chapter anchor")

            target_q_id = row[0]
            block_type = "responsive"
            content = text_stripped[3:].strip() if text_stripped.startswith("[R]") else text_stripped.strip()

            cur.execute("""
                INSERT INTO answer_blocks (
                    question_id, block_order, block_type, content, reference, image_ref
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (target_q_id, block_order, block_type, content, None, None))

            stats["inserted"] += 1
            stats["with_q_id"] += 1
            stats["responsive"] += 1
            block_order += 1
            continue

        is_question_para = False
        q_num = None

        if has_blue:
            if red_digits:
                q_num = int("".join(red_digits))
                is_question_para = True
            else:
                q_num = _extract_leading_qnum(text_stripped)
                if q_num is not None:
                    is_question_para = True

        if is_question_para and q_num is not None:
            key = (current_section, current_chapter, q_num)
            if key in q_map:
                current_q_id = q_map[key]
                block_order = 0
                if first_q_id_in_chapter is None:
                    first_q_id_in_chapter = current_q_id
                # Trailing text check
                if "?" in text:
                    parts = text.split("?", 1)
                    if len(parts) > 1:
                        trailing = parts[1].strip()
                        if trailing:
                            target_q_id = current_q_id or first_q_id_in_chapter
                            if target_q_id is None:
                                continue
                            if current_q_id is None:
                                raise RuntimeError("Invariant violated: no active chapter anchor")
                            cur.execute("""
                                INSERT INTO answer_blocks (
                                    question_id, block_order, block_type, content, reference, image_ref
                                ) VALUES (?, ?, ?, ?, ?, ?)
                            """, (target_q_id, block_order, "answer", trailing, None, None))
                            stats["inserted"] += 1
                            stats["with_q_id"] += 1
                            block_order += 1
            
            # Stop processing this paragraph
            continue

        starts_with_r = normalized.startswith("[R]")
        # Removed the early responsive-reading insertion and continue block as per instructions

        block_type = "answer"
        content = text
        image_ref = None
        # Removed line: target_q_id = current_q_id or first_q_id_in_chapter

        if text_stripped.startswith("[P]"):
            block_type = "poetry"
            content = text_stripped[3:].lstrip()
            stats["poetry"] += 1
        elif text_stripped.startswith("[N]"):
            block_type = "note"
            content = text[3:].strip()
            stats["notes"] += 1
        elif text_stripped.startswith("[Pic:"):
            m = PIC_RE.match(text_stripped)
            if m:
                fname = m.group(1).strip()
                fname_lower = fname.lower()
                block_type = "image"
                content = f"[Pic:{fname}]"
                image_ref = img_map.get(fname_lower)
                stats["images"] += 1


        # Resolve target question_id
        if current_q_id is None and current_chapter > 0:
            cur.execute("""
                SELECT id FROM questions
                WHERE section_number=? AND chapter_number=? AND question_number=0
            """, (current_section, current_chapter))
            row = cur.fetchone()
            if not row:
                raise RuntimeError("Invariant violated: no chapter anchor for content block")
            current_q_id = row[0]

        target_q_id = current_q_id or first_q_id_in_chapter

        # Chapter-level fallback
        if target_q_id is None:
            cur.execute("""
                SELECT id FROM questions
                WHERE section_number=? AND chapter_number=? AND question_number=0
            """, (current_section, current_chapter))
            row = cur.fetchone()
            if not row:
                raise RuntimeError("Invariant violated: no chapter anchor for content block")
            target_q_id = row[0]

        cur.execute("""
            INSERT INTO answer_blocks (
                question_id, block_order, block_type, content, reference, image_ref
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, (target_q_id, block_order, block_type, content, None, image_ref))
        
        stats["inserted"] += 1
        stats["with_q_id"] += 1

        if block_type == "responsive" and debug:
            print(f"[TRACE] Responsive INSERTED | q_id={target_q_id} order={block_order}")

        block_order += 1

    conn.commit()

    cur.execute("SELECT COUNT(*) FROM answer_blocks WHERE question_id IS NULL")
    if cur.fetchone()[0] != 0:
        raise RuntimeError("Post-import validation failed: NULL question_id found")

    cur.execute("""
        SELECT COUNT(DISTINCT chapter_number)
        FROM questions
        WHERE chapter_number > 0
    """)
    chapter_count = cur.fetchone()[0]

    # Global introduction anchor (section=0, chapter=0, question=0)
    cur.execute("""
        SELECT COUNT(*)
        FROM questions
        WHERE section_number = 0 AND chapter_number = 0 AND question_number = 0
    """)
    global_intro_anchor_count = cur.fetchone()[0]

    # Section introduction anchors (one per section, section>0, chapter=0, question=0)
    cur.execute("""
        SELECT COUNT(*)
        FROM questions
        WHERE section_number > 0 AND chapter_number = 0 AND question_number = 0
    """)
    section_intro_anchor_count = cur.fetchone()[0]

    if debug:
        print("[TRACE] Import finished")

    print(f"Total blocks inserted: {stats['inserted']}")
    print(f"Blocks with question_id: {stats['with_q_id']}")
    print(f"Notes count: {stats['notes']}")
    print(f"Poetry count: {stats['poetry']}")
    print(f"Responsive reading count: {stats['responsive']}")
    print(f"Image links created: {stats['images']}")
    print(f"Chapters present: {chapter_count}")
    print(f"Sections present: {section_intro_anchor_count}")
    print(f"Global introduction anchors present: {global_intro_anchor_count}")
    cur.execute("""
        SELECT COUNT(*)
        FROM answer_blocks ab
        JOIN questions q ON ab.question_id = q.id
        WHERE q.section_number = 0 AND q.chapter_number = 0 AND q.question_number = 0
    """)
    print(f"Global introduction blocks (linked to section=0 intro): {cur.fetchone()[0]}")

    conn.close()

if __name__ == "__main__":
    main()
