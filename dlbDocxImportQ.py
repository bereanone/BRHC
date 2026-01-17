import sqlite3
import re
import os
from docx import Document
from docx.shared import RGBColor

INPUT_DOC = "docs/references/BRHC1914-Qmarked.docx"
DB_PATH = "assets/databases/brhc.db"

def main():
    if not os.path.exists(INPUT_DOC):
        raise FileNotFoundError(f"Missing input document: {INPUT_DOC}")
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(f"Missing database: {DB_PATH}")

    # Connect to database
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Clear existing data
    cur.execute("DELETE FROM questions")

    # Load document
    doc = Document(INPUT_DOC)

    # Regex patterns
    section_re = re.compile(r"Section\s+(\d+)", re.IGNORECASE)
    chapter_re = re.compile(r"Chapter\s+(\d+)", re.IGNORECASE)

    # Colors
    red_color = RGBColor(255, 0, 0)
    blue_color = RGBColor(0, 0, 255)

    # State tracking
    current_section_title = ""
    current_section_number = 0
    current_chapter_title = ""
    current_chapter_number = 0

    # Statistics
    total_sections = 0
    total_chapters = 0
    total_questions = 0
    sequence_in_book = 0

    for para in doc.paragraphs:
        text = para.text.strip()
        if not text:
            continue

        # 1. SECTIONS
        if text.startswith("[S]"):
            total_sections += 1
            # Extract title after [S]
            raw_title = text[3:].strip()
            current_section_title = raw_title
            
            # Extract number
            match = section_re.search(raw_title)
            if match:
                current_section_number = int(match.group(1))
            else:
                current_section_number = 0
            continue

        # 2. CHAPTERS
        if text.startswith("[Ch]"):
            total_chapters += 1
            # Extract title after [Ch]
            raw_title = text[4:].strip()
            current_chapter_title = raw_title

            # Extract number
            match = chapter_re.search(raw_title)
            if match:
                current_chapter_number = int(match.group(1))
            else:
                current_chapter_number = 0
            continue

        # 3. QUESTIONS
        # Must have valid section and chapter context
        if current_section_number == 0 or current_chapter_number == 0:
            continue

        # Accumulate colored text from runs
        red_digits = []
        question_text_parts = []
        has_black_text = False
        seen_blue_text = False

        for run in para.runs:
            if not run.text:
                continue

            font = run.font
            color = font.color.rgb if font and font.color else None

            if color == red_color:
                for char in run.text:
                    if char.isdigit():
                        red_digits.append(char)
                continue

            if color == blue_color:
                seen_blue_text = True
                question_text_parts.append(run.text)
                continue

            # Allow leading punctuation/whitespace BEFORE blue text
            if not seen_blue_text:
                if run.text.strip() in {".", "", " "}:
                    continue

            # Anything else is invalid black text
            has_black_text = True

        if not red_digits:
            continue

        question_number = int("".join(red_digits))
        question_text = "".join(question_text_parts).strip()
        # Normalize leading punctuation artifacts from Word run boundaries
        question_text = question_text.lstrip(" .\t")

        # Split compound blue text if '?' present with trailing text
        trailing_text = ""
        if '?' in question_text:
            qpos = question_text.find('?')
            if qpos < len(question_text) - 1:
                trailing_text = question_text[qpos+1:].lstrip()
                question_text = question_text[:qpos+1]

        # Update counters
        sequence_in_book += 1
        total_questions += 1

        # Insert into database
        cur.execute("""
            INSERT INTO questions (
                section_number,
                section_title,
                chapter_number,
                chapter_title,
                question_number,
                question_text,
                sequence_in_book,
                sequence_in_chapter,
                contains_commentary,
                contains_poetry,
                needs_review
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0)
        """, (
            current_section_number,
            current_section_title,
            current_chapter_number,
            current_chapter_title,
            question_number,
            question_text,
            sequence_in_book,
            question_number
        ))

        if trailing_text:
            cur.execute("""
                INSERT INTO answer_blocks (
                    question_number,
                    block_type,
                    content,
                    block_order
                ) VALUES (?, ?, ?, ?)
            """, (
                question_number,
                "answer",
                trailing_text,
                1
            ))

    conn.commit()
    conn.close()

    print(f"Total sections detected: {total_sections}")
    print(f"Total chapters detected: {total_chapters}")
    print(f"Total questions imported: {total_questions}")

if __name__ == "__main__":
    main()
