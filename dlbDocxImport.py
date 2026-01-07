from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
from dataclasses import dataclass
from typing import Iterable, Sequence

from docx import Document
from docx.oxml.ns import qn
from docx.shared import RGBColor

INPUT_DOC = "docs/references/BRHC1914-final.docx"
DB_PATH = "assets/databases/brhc.db"

CHAPTER_RE = re.compile(r"^(?:\[Ch\]\s*)?Chapter\s+(\d+)", re.IGNORECASE)
KNOWN_MARKERS = {"[S]", "[Ch]", "[Q]", "[A]", "[N]", "[P]", "[T]"}
DOT_LEADER_RE = re.compile(r"\.{2,}")
SCRIPTURE_REF_RE = re.compile(r"\b[A-Za-z][A-Za-z\.]+\s+\d+[:\.]\d")
PIC_TAG_RE = re.compile(r"\[Pic:\s*([^\]]+?)\s*\]", re.IGNORECASE)


def _is_blue(run) -> bool:
    if hasattr(run, "is_blue"):
        return bool(run.is_blue)
    color = run.font.color
    return color is not None and color.rgb == RGBColor(0, 0, 255)

def _is_effective_bold(run, fallback: bool | None = None) -> bool:
    if run.bold is True:
        return True
    if run.bold is False:
        return False
    if fallback is True:
        return True
    try:
        style = getattr(run, "style", None)
        if style is not None and style.font is not None and style.font.bold is True:
            return True
    except AttributeError:
        pass
    try:
        font = getattr(run, "font", None)
        if font is not None and font.bold is True:
            return True
    except AttributeError:
        pass
    return False


def _is_effective_italic(run, fallback: bool | None = None) -> bool:
    if run.italic is True:
        return True
    if run.italic is False:
        return False
    if fallback is True:
        return True
    try:
        style = getattr(run, "style", None)
        if style is not None and style.font is not None and style.font.italic is True:
            return True
    except AttributeError:
        pass
    try:
        font = getattr(run, "font", None)
        if font is not None and font.italic is True:
            return True
    except AttributeError:
        pass
    return False


def _runs_to_markup(runs: Sequence) -> tuple[str, bool]:
    output: list[str] = []
    has_markup = False
    current_bold = None
    current_italic = None

    def close_tags() -> None:
        nonlocal current_bold, current_italic
        if current_italic:
            output.append("</em>")
        if current_bold:
            output.append("</strong>")
        current_bold = None
        current_italic = None

    def open_tags(bold: bool, italic: bool) -> None:
        nonlocal has_markup, current_bold, current_italic
        if bold:
            output.append("<strong>")
            has_markup = True
        if italic:
            output.append("<em>")
            has_markup = True
        current_bold = bold
        current_italic = italic

    for run in runs:
        text = run.text
        if not text:
            continue
        bold = bool(run.bold)
        italic = bool(run.italic)
        if current_bold is None and current_italic is None:
            open_tags(bold, italic)
        elif bold != current_bold or italic != current_italic:
            close_tags()
            open_tags(bold, italic)
        output.append(text)

    close_tags()
    return "".join(output), has_markup


@dataclass(frozen=True)
class SimpleRun:
    text: str
    bold: bool
    italic: bool
    is_blue: bool


def _split_runs_on_marker(runs: Sequence[SimpleRun], marker: str) -> list[list[SimpleRun]]:
    total_text = "".join(run.text for run in runs)
    idx = total_text.find(marker)
    if idx == -1 or total_text.strip().startswith(marker):
        return [list(runs)]
    before: list[SimpleRun] = []
    after: list[SimpleRun] = []
    cursor = 0
    for run in runs:
        text = run.text
        if not text:
            continue
        next_cursor = cursor + len(text)
        if idx >= next_cursor:
            before.append(run)
        elif idx <= cursor:
            after.append(run)
        else:
            split_at = idx - cursor
            before_text = text[:split_at]
            after_text = text[split_at:]
            if before_text:
                before.append(
                    SimpleRun(
                        text=before_text,
                        bold=run.bold,
                        italic=run.italic,
                        is_blue=run.is_blue,
                    )
                )
            if after_text:
                after.append(
                    SimpleRun(
                        text=after_text,
                        bold=run.bold,
                        italic=run.italic,
                        is_blue=run.is_blue,
                    )
                )
        cursor = next_cursor
    return [before, after] if after else [before]


def _strip_marker_prefix_runs(
    runs: Sequence[SimpleRun], marker: str
) -> list[SimpleRun]:
    total_text = "".join(run.text for run in runs)
    stripped = total_text.lstrip()
    if not stripped.startswith(marker):
        return list(runs)
    offset = len(total_text) - len(stripped)
    start = offset
    end = start + len(marker)
    updated: list[SimpleRun] = []
    cursor = 0
    for run in runs:
        text = run.text
        if not text:
            continue
        next_cursor = cursor + len(text)
        if next_cursor <= start or cursor >= end:
            updated.append(run)
        else:
            if cursor < start:
                before_text = text[: start - cursor]
                if before_text:
                    updated.append(
                        SimpleRun(
                            text=before_text,
                            bold=run.bold,
                            italic=run.italic,
                            is_blue=run.is_blue,
                        )
                    )
            if next_cursor > end:
                after_text = text[end - cursor :]
                if after_text:
                    updated.append(
                        SimpleRun(
                            text=after_text,
                            bold=run.bold,
                            italic=run.italic,
                            is_blue=run.is_blue,
                        )
                    )
        cursor = next_cursor
    return updated


def _find_title_reference_span(text: str) -> tuple[str, str, int, int] | None:
    def looks_like_scripture(candidate: str) -> bool:
        return bool(SCRIPTURE_REF_RE.search(candidate))

    if "\t" in text:
        idx = text.find("\t")
        left = text[:idx].strip()
        right = text[idx + 1 :].strip()
        if left and right and looks_like_scripture(right):
            return left, right, idx, idx + 1
    match = DOT_LEADER_RE.search(text)
    if match:
        left = text[: match.start()].strip()
        right = text[match.end() :].strip()
        if left and right and looks_like_scripture(right):
            return left, right, match.start(), match.end()
    return None


def _split_runs_by_span(
    runs: Sequence[SimpleRun], start: int, end: int
) -> tuple[list[SimpleRun], list[SimpleRun]]:
    left: list[SimpleRun] = []
    right: list[SimpleRun] = []
    cursor = 0
    for run in runs:
        text = run.text
        if not text:
            continue
        run_start = cursor
        run_end = cursor + len(text)
        if run_end <= start:
            left.append(run)
        elif run_start >= end:
            right.append(run)
        else:
            before_len = max(0, start - run_start)
            after_len = max(0, run_end - end)
            if before_len > 0:
                left.append(
                    SimpleRun(
                        text=text[:before_len],
                        bold=run.bold,
                        italic=run.italic,
                        is_blue=run.is_blue,
                    )
                )
            if after_len > 0:
                right.append(
                    SimpleRun(
                        text=text[len(text) - after_len :],
                        bold=run.bold,
                        italic=run.italic,
                        is_blue=run.is_blue,
                    )
                )
        cursor = run_end
    return left, right


def _paragraph_image_parts(paragraph) -> Iterable:
    blips = paragraph._element.xpath(".//a:blip")
    for blip in blips:
        rid = blip.get(qn("r:embed"))
        if not rid:
            continue
        part = paragraph.part.related_parts.get(rid)
        if part is None:
            continue
        yield part



def _insert_doc_block(
    cur: sqlite3.Cursor,
    block_id: int,
    section_title: str | None,
    chapter_title: str | None,
    block_order: int,
    block_type: str,
    raw_text: str | None,
    normalized_text: str | None,
    table_json: str | None = None,
) -> None:
    cur.execute(
        """
        INSERT INTO doc_blocks (
            block_id, section_title, chapter_title, block_order, block_type,
            raw_text, normalized_text, table_json, image_blob_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)
        """,
        (
            block_id,
            section_title,
            chapter_title,
            block_order,
            block_type,
            raw_text,
            normalized_text,
            table_json,
        ),
    )


def _insert_question(
    cur: sqlite3.Cursor,
    block_id: int,
    question_number: int,
    question_text: str,
    section_title: str | None,
    chapter_title: str | None,
) -> None:
    cur.execute(
        """
        INSERT INTO d_questions (
            block_id, question_number, question_text, section_title, chapter_title
        ) VALUES (?, ?, ?, ?, ?)
        """,
        (block_id, question_number, question_text, section_title, chapter_title),
    )


def _insert_question_row(
    cur: sqlite3.Cursor,
    section_title: str | None,
    chapter_title: str | None,
    chapter_number: int | None,
    question_number: int,
    question_text: str,
) -> None:
    cur.execute(
        """
        INSERT INTO questions (
            section_title, chapter_title, chapter_number, content_type,
            question_number, question_text, answer_text
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            section_title,
            chapter_title,
            chapter_number,
            "question",
            question_number,
            question_text,
            None,
        ),
    )


def _clear_live_tables(cur: sqlite3.Cursor) -> None:
    cur.execute("DELETE FROM doc_blocks")
    cur.execute("DELETE FROM d_questions")
    cur.execute("DELETE FROM questions")
    cur.execute("DELETE FROM brhc_chapters")
    cur.execute("DELETE FROM brhc_sections")




def _note_heading(text: str) -> bool:
    trimmed = re.sub(r"[^A-Za-z]", "", text)
    return bool(trimmed) and trimmed.upper() == trimmed


def _run_import() -> None:
    if not os.path.exists(INPUT_DOC):
        raise FileNotFoundError(f"Missing input document: {INPUT_DOC}")
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(f"Missing database: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH, timeout=30)
    cur = conn.cursor()
    cur.execute("PRAGMA foreign_keys = OFF")
    cur.execute("PRAGMA busy_timeout = 30000")
    cur.execute("BEGIN")

    _clear_live_tables(cur)
    cur.execute("SELECT filename FROM brhc_images")
    image_filenames = {
        (row[0] or "").lower() for row in cur.fetchall() if row and row[0]
    }

    doc = Document(INPUT_DOC)

    section_order = 0
    chapter_order = 0
    current_section_title = None
    current_section_id = None
    current_chapter_title = None
    current_chapter_num = None
    block_order = 0
    question_counter = 0
    block_id = 1

    sections_total = 0
    chapters_processed = 0
    questions_total = 0
    notes_total = 0
    poetry_total = 0
    responsive_total = 0
    tables_total = 0
    title_refs_total = 0
    image_links_total = 0

    anomalies: list[str] = []
    missing_pic_filenames: list[str] = []

    intro_active = True
    aggregated_type: str | None = None
    aggregated_lines: list[str] = []
    aggregated_markup: list[str] = []
    aggregated_has_markup = False

    current_mode: str | None = None
    current_buffer: list[SimpleRun] = []
    current_has_text = False
    note_active = False
    note_lines: list[str] = []
    note_markup: list[str] = []
    note_has_markup = False
    def allocate_block_id() -> int:
        nonlocal block_id
        next_id = block_id
        block_id += 1
        return next_id

    def attach_images(target_id: int) -> None:
        return

    def _insert_image_block(filename: str) -> None:
        nonlocal block_order, image_links_total
        block_order += 1
        token = f"[Pic: {filename}]"
        target_id = allocate_block_id()
        _insert_doc_block(
            cur,
            target_id,
            current_section_title,
            current_chapter_title,
            block_order,
            "image",
            token,
            token,
        )
        image_links_total += 1

    def flush_note() -> None:
        nonlocal note_active, note_lines, note_markup, note_has_markup
        nonlocal block_order, notes_total
        if not note_active or not note_lines:
            note_active = False
            note_lines = []
            note_markup = []
            note_has_markup = False
            return
        block_order += 1
        raw_text = "\n".join(note_lines).strip()
        normalized_text = (
            "\n".join(note_markup).strip() if note_has_markup else raw_text
        )
        target_id = allocate_block_id()
        _insert_doc_block(
            cur,
            target_id,
            current_section_title,
            current_chapter_title,
            block_order,
            "note",
            raw_text,
            normalized_text,
        )
        attach_images(target_id)
        notes_total += 1
        note_active = False
        note_lines = []
        note_markup = []
        note_has_markup = False

    def flush_aggregate() -> None:
        nonlocal aggregated_type, aggregated_lines, aggregated_markup
        nonlocal aggregated_has_markup, block_order, poetry_total
        nonlocal responsive_total, tables_total
        if aggregated_type is None or not aggregated_lines:
            aggregated_type = None
            aggregated_lines = []
            aggregated_markup = []
            aggregated_has_markup = False
            return
        block_order += 1
        raw_text = "\n".join(aggregated_lines).strip()
        normalized_text = (
            "\n".join(aggregated_markup).strip() if aggregated_has_markup else raw_text
        )
        table_json = None
        if aggregated_type == "table":
            rows = []
            for line in aggregated_lines:
                rows.append([cell for cell in line.split("\t")])
            table_json = json.dumps(rows)
        target_id = allocate_block_id()
        _insert_doc_block(
            cur,
            target_id,
            current_section_title,
            current_chapter_title,
            block_order,
            aggregated_type,
            raw_text,
            normalized_text,
            table_json=table_json,
        )
        attach_images(target_id)
        if aggregated_type == "poetry":
            poetry_total += 1
        elif aggregated_type == "responsive":
            responsive_total += 1
        elif aggregated_type == "table":
            tables_total += 1
        aggregated_type = None
        aggregated_lines = []
        aggregated_markup = []
        aggregated_has_markup = False

    def flush_qa_block() -> None:
        nonlocal current_mode, current_buffer, current_has_text, block_order
        nonlocal question_counter, questions_total
        if current_mode is None or not current_buffer:
            current_mode = None
            current_buffer = []
            current_has_text = False
            return
        raw_text = "".join(run.text for run in current_buffer).strip()
        markup, has_markup = _runs_to_markup(current_buffer)
        block_order += 1
        # NOTE: Question identity is structural (blue text / numbering), not grammatical.
        # Declarative statements without '?' may still be questions and must remain unchanged.
        block_type = "question" if current_mode == "question" else "answer"
        target_id = allocate_block_id()
        normalized_text = markup if has_markup else raw_text
        _insert_doc_block(
            cur,
            target_id,
            current_section_title,
            current_chapter_title,
            block_order,
            block_type,
            raw_text,
            normalized_text,
        )
        attach_images(target_id)
        if block_type == "question":
            question_counter += 1
            questions_total += 1
            _insert_question(
                cur,
                target_id,
                question_counter,
                raw_text,
                current_section_title,
                current_chapter_title,
            )
            _insert_question_row(
                cur,
                current_section_title,
                current_chapter_title,
                current_chapter_num,
                question_counter,
                raw_text,
            )
        current_mode = None
        current_buffer = []
        current_has_text = False

    def start_mode(mode: str) -> None:
        nonlocal current_mode
        if current_mode is None:
            current_mode = mode
            return
        if current_mode != mode:
            flush_qa_block()
            current_mode = mode

    for para in doc.paragraphs:
        para_style = getattr(para, "style", None)
        para_font = para_style.font if para_style is not None else None
        para_bold = para_font.bold is True if para_font is not None else False
        para_italic = para_font.italic is True if para_font is not None else False
        base_runs = [
            SimpleRun(
                text=run.text,
                bold=_is_effective_bold(run, para_bold),
                italic=_is_effective_italic(run, para_italic),
                is_blue=_is_blue(run),
            )
            for run in para.runs
            if run.text
        ]
        if not base_runs and para.text:
            base_runs = [
                SimpleRun(text=para.text, bold=False, italic=False, is_blue=False)
            ]

        segments = _split_runs_on_marker(base_runs, "[N]")

        for segment in segments:
            raw_text = "".join(run.text for run in segment)
            pic_matches = list(PIC_TAG_RE.finditer(raw_text))
            if pic_matches:
                for match in pic_matches:
                    filename = match.group(1).strip()
                    if filename:
                        _insert_image_block(filename)
                        if filename.lower() not in image_filenames:
                            missing_pic_filenames.append(filename)
                raw_text = PIC_TAG_RE.sub("", raw_text)
            stripped = raw_text.strip()

            if aggregated_type is not None:
                boundary = (
                    stripped.startswith("[S]")
                    or stripped.startswith("[Ch]")
                    or stripped.startswith("[N]")
                    or stripped.startswith("[R]")
                    or stripped.startswith("[T]")
                    or CHAPTER_RE.match(stripped)
                )
                if boundary:
                    flush_aggregate()
                else:
                    markup, has_markup = _runs_to_markup(segment)
                    aggregated_lines.append(raw_text)
                    aggregated_markup.append(markup)
                    aggregated_has_markup = aggregated_has_markup or has_markup
                    continue

            if note_active:
                boundary = (
                    stripped.startswith("[S]")
                    or stripped.startswith("[Ch]")
                    or stripped.startswith("[N]")
                    or stripped.startswith("[P]")
                    or stripped.startswith("[R]")
                    or stripped.startswith("[T]")
                    or CHAPTER_RE.match(stripped)
                    or any(_is_blue(run) for run in segment)
                )
                if boundary:
                    flush_note()
                else:
                    markup, has_markup = _runs_to_markup(segment)
                    note_lines.append(raw_text)
                    note_markup.append(markup)
                    note_has_markup = note_has_markup or has_markup
                    continue

            if not stripped:
                if current_mode is not None and current_has_text:
                    current_buffer.append(
                        SimpleRun(text="\n", bold=False, italic=False, is_blue=False)
                    )
                continue

            if stripped.startswith("[") and "]" in stripped:
                marker = stripped[: stripped.index("]") + 1]
                if marker in KNOWN_MARKERS:
                    pass
                elif marker.lower().startswith("[pic:"):
                    pass
                else:
                    pass

            ch_match = CHAPTER_RE.match(stripped)
            if ch_match:
                flush_note()
                flush_aggregate()
                flush_qa_block()
                current_chapter_num = int(ch_match.group(1))
                content = stripped.replace("[Ch]", "", 1).strip()
                current_chapter_title = content
                question_counter = 0
                block_order = 0
                chapter_order += 1
                chapters_processed += 1
                intro_active = False
                cur.execute(
                    "INSERT INTO brhc_chapters (section_id, chapter_title, order_index) VALUES (?, ?, ?)",
                    (current_section_id, current_chapter_title, chapter_order),
                )
                block_order += 1
                target_id = allocate_block_id()
                _insert_doc_block(
                    cur,
                    target_id,
                    current_section_title,
                    current_chapter_title,
                    block_order,
                    "chapter",
                    content,
                    content,
                )
                attach_images(target_id)
                continue

            if stripped.startswith("[S]"):
                flush_note()
                flush_aggregate()
                flush_qa_block()
                content = stripped.replace("[S]", "", 1).strip()
                current_section_title = content
                section_order += 1
                sections_total += 1
                cur.execute(
                    "INSERT INTO brhc_sections (section_title, order_index) VALUES (?, ?)",
                    (current_section_title, section_order),
                )
                current_section_id = int(cur.lastrowid)
                block_order += 1
                target_id = allocate_block_id()
                _insert_doc_block(
                    cur,
                    target_id,
                    current_section_title,
                    None,
                    block_order,
                    "section",
                    content,
                    content,
                )
                attach_images(target_id)
                intro_active = False
                continue

            if intro_active and stripped.startswith("[I]"):
                flush_note()
                flush_qa_block()
                intro_runs = _strip_marker_prefix_runs(segment, "[I]")
                content = "".join(run.text for run in intro_runs).strip()
                if not content:
                    continue
                markup, has_markup = _runs_to_markup(intro_runs)
                block_type = (
                    "intro_heading" if _note_heading(content) else "intro_paragraph"
                )
                block_order += 1
                target_id = allocate_block_id()
                _insert_doc_block(
                    cur,
                    target_id,
                    None,
                    None,
                    block_order,
                    block_type,
                    content,
                    markup if has_markup else content,
                )
                attach_images(target_id)
                continue

            if intro_active and current_section_title is None and current_chapter_title is None:
                flush_note()
                flush_qa_block()
                content = raw_text.strip()
                if not content:
                    continue
                markup, has_markup = _runs_to_markup(segment)
                block_type = (
                    "intro_heading" if _note_heading(content) else "intro_paragraph"
                )
                block_order += 1
                target_id = allocate_block_id()
                _insert_doc_block(
                    cur,
                    target_id,
                    None,
                    None,
                    block_order,
                    block_type,
                    content,
                    markup if has_markup else content,
                )
                attach_images(target_id)
                continue

            if current_chapter_title is None:
                if any(_is_blue(run) for run in segment):
                    anomalies.append(
                        f"Orphan blue question before chapter: {stripped[:80]}"
                    )
                continue

            if stripped.startswith("[P]"):
                flush_note()
                flush_qa_block()
                aggregated_type = "poetry"
                content = stripped.replace("[P]", "", 1).strip()
                markup, has_markup = _runs_to_markup(segment)
                aggregated_lines = [content]
                aggregated_markup = [markup]
                aggregated_has_markup = has_markup
                continue

            if stripped.startswith("[R]"):
                flush_note()
                flush_qa_block()
                aggregated_type = "responsive"
                content = stripped.replace("[R]", "", 1).strip()
                markup, has_markup = _runs_to_markup(segment)
                aggregated_lines = [content]
                aggregated_markup = [markup]
                aggregated_has_markup = has_markup
                continue

            if stripped.startswith("[T]"):
                flush_note()
                flush_qa_block()
                aggregated_type = "table"
                content = stripped.replace("[T]", "", 1).strip()
                aggregated_lines = [content]
                aggregated_markup = []
                aggregated_has_markup = False
                continue

            if stripped.startswith("[N]"):
                flush_qa_block()
                markup, has_markup = _runs_to_markup(segment)
                note_active = True
                note_lines = [raw_text.strip()]
                note_markup = [markup]
                note_has_markup = has_markup
                continue

            split_pair = _find_title_reference_span(raw_text)
            if split_pair:
                flush_note()
                flush_qa_block()
                left, right, span_start, span_end = split_pair
                left_runs, right_runs = _split_runs_by_span(segment, span_start, span_end)
                left_markup, left_has_markup = _runs_to_markup(left_runs)
                right_markup, right_has_markup = _runs_to_markup(right_runs)
                left_value = left_markup if left_has_markup else left
                right_value = right_markup if right_has_markup else right
                block_order += 1
                target_id = allocate_block_id()
                payload = json.dumps({"left": left, "right": right})
                _insert_doc_block(
                    cur,
                    target_id,
                    current_section_title,
                    current_chapter_title,
                    block_order,
                    "title_ref",
                    f"{left}\n{right}",
                    f"{left_value}\n{right_value}",
                    table_json=payload,
                )
                attach_images(target_id)
                title_refs_total += 1
                continue

            runs = [run for run in segment if run.text]
            if runs:
                flush_note()
                first_mode = "question" if _is_blue(runs[0]) else "answer"
                if current_mode is not None and current_has_text:
                    if current_mode == first_mode:
                        current_buffer.append(
                            SimpleRun(text="\n", bold=False, italic=False, is_blue=False)
                        )
                    else:
                        flush_qa_block()
            for run in runs:
                if not run.text:
                    continue
                mode = "question" if _is_blue(run) else "answer"
                start_mode(mode)
                current_buffer.append(run)
                current_has_text = True

    flush_aggregate()
    flush_qa_block()
    flush_note()

    if missing_pic_filenames:
        anomalies.append(
            "Missing [Pic] filenames in brhc_images: "
            + ", ".join(sorted(set(missing_pic_filenames)))
        )

    cur.execute("PRAGMA foreign_keys = ON")
    conn.commit()

    print("Import complete (live tables).")
    print(f"Sections imported: {sections_total}")
    print(f"Chapters imported: {chapters_processed}")
    print(f"Questions renumbered: {questions_total}")
    print(f"Notes imported: {notes_total}")
    print(f"Poetry blocks imported: {poetry_total}")
    print(f"Responsive readings imported: {responsive_total}")
    print(f"Tables imported: {tables_total}")
    print(f"Title-ref imported: {title_refs_total}")
    print(f"Image links created: {image_links_total}")
    if anomalies:
        print("Anomalies:")
        for entry in anomalies:
            print(f"- {entry}")

    conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="BRHC live import")
    parser.add_argument("--import", dest="do_import", action="store_true")
    args = parser.parse_args()
    if not args.do_import:
        parser.error("Use --import to run the live import")
    _run_import()


if __name__ == "__main__":
    main()
