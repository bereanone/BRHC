import json
import os
import re
from collections import Counter
from docx import Document

INPUT_DOC = "docs/references/BRHC1914-Qmarked.docx"

SECTION_RE = re.compile(r"Section\s+(\d+)", re.IGNORECASE)
CHAPTER_RE = re.compile(r"Chapter\s+(\d+)", re.IGNORECASE)
PIC_RE = re.compile(r"\[Pic:\s*([^\]]+)\]", re.IGNORECASE)
QNUM_START_RE = re.compile(r"^\s*(\d{1,3})(?:\s*[\.\)]|\s+)")
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


def _is_close_color(rgb, target, tol=40):
    t = _rgb_tuple(rgb)
    if not t:
        return False
    return all(abs(t[i] - target[i]) <= tol for i in range(3))


def _wrap_color_markers(text, rgb):
    if _is_close_color(rgb, (112, 48, 160)):
        return f"[L]{text}[/L]"
    if _is_close_color(rgb, (0, 176, 80)):
        return f"[R]{text}[/R]"
    return text


def _extract_leading_qnum(text):
    m = QNUM_START_RE.match(text)
    if m:
        return int(m.group(1))
    return None


def _strip_marker(text, marker):
    if text.startswith(marker):
        remainder = text[len(marker):]
        if remainder.startswith(" "):
            remainder = remainder[1:]
        return remainder
    return text


def _render_runs_with_emphasis(paragraph):
    parts = []
    last_tag = None  # track last wrapper to merge adjacent runs

    for run in paragraph.runs:
        if not run.text:
            continue

        text = _wrap_color_markers(
            run.text,
            run.font.color.rgb if run.font and run.font.color else None,
        )

        is_bold = bool(run.bold or (run.font and run.font.bold))
        is_italic = bool(run.italic or (run.font and run.font.italic))
        is_underline = bool(getattr(run, "underline", False))
        is_emphasis = (
            bool(getattr(run.style, "name", ""))
            and "emphasis" in getattr(run.style, "name", "").lower()
        )

        # determine wrapper (prefer <em> for emphasis, <i> for italic)
        wrapper = None
        if is_emphasis:
            wrapper = "em"
        elif is_italic:
            wrapper = "i"

        # apply bold first (outer)
        if is_bold and not text.strip().startswith("<strong>"):
            text = f"<strong>{text}</strong>"

        # merge adjacent identical emphasis tags
        if wrapper:
            if last_tag == wrapper and parts and parts[-1].endswith(f"</{wrapper}>"):
                # reopen previous tag and append without nesting
                parts[-1] = parts[-1][:-len(f"</{wrapper}>")] + text + f"</{wrapper}>"
            else:
                if not text.strip().startswith(f"<{wrapper}>"):
                    text = f"<{wrapper}>{text}</{wrapper}>"
                parts.append(text)
            last_tag = wrapper
        else:
            # underline (non-merging)
            if is_underline and not text.strip().startswith("<u>"):
                text = f"<u>{text}</u>"
            parts.append(text)
            last_tag = None

    return "".join(parts)

def _render_run_with_emphasis(run):
    text = _wrap_color_markers(
        run.text,
        run.font.color.rgb if run.font and run.font.color else None,
    )
    if not text:
        return ""

    is_bold = bool(run.bold or (run.font and run.font.bold))
    is_italic = bool(run.italic or (run.font and run.font.italic))
    is_underline = bool(getattr(run, "underline", False))
    is_emphasis = (
        bool(getattr(run.style, "name", ""))
        and "emphasis" in getattr(run.style, "name", "").lower()
    )

    wrapper = None
    if is_emphasis:
        wrapper = "em"
    elif is_italic:
        wrapper = "i"

    if is_bold and not text.strip().startswith("<strong>"):
        text = f"<strong>{text}</strong>"
    if wrapper and not text.strip().startswith(f"<{wrapper}>"):
        text = f"<{wrapper}>{text}</{wrapper}>"
    if is_underline and not text.strip().startswith("<u>"):
        text = f"<u>{text}</u>"
    return text


def _strip_marker_from_rendered(text, marker):
    if text.startswith(marker):
        remainder = text[len(marker):]
        if remainder.startswith(" "):
            remainder = remainder[1:]
        return remainder
    return text


def classify_docx(doc_path=INPUT_DOC):
    doc = Document(doc_path)
    tokens = []
    counts = Counter()
    transitions = []

    current_section = 0
    current_chapter = 0
    current_question = None
    pending_qnum = None
    in_global_intro = True
    in_section_intro = False

    poetry_mode = False
    chapter_has_question = False

    for para in doc.paragraphs:
        raw_text = para.text
        if raw_text is None:
            continue
        raw_text_stripped = raw_text.strip()
        forced_qnum = _extract_leading_qnum(raw_text_stripped)
        if not raw_text_stripped:
            if poetry_mode:
                tokens.append({
                    "kind": "poetry",
                    "section": current_section,
                    "chapter": current_chapter,
                    "question": current_question,
                    "text": "",
                    "meta": {"block_type": "poetry"},
                })
                counts["poetry"] += 1
            continue
        text = _render_runs_with_emphasis(para)
        if text is None:
            continue

        is_bold_para = False

        # Paragraph style bold (Heading styles, etc.)
        if para.style and para.style.name and "heading" in para.style.name.lower():
            is_bold_para = True
        elif para.style and para.style.name and "title" in para.style.name.lower():
            is_bold_para = True
        elif para.style and para.style.font and para.style.font.bold:
            is_bold_para = True
        else:
            # Run-level bold: Word often uses run.font.bold, not run.bold
            bold_runs = [
                r for r in para.runs
                if r.text and r.text.strip() and r.font and r.font.bold
            ]
            if bold_runs and len(bold_runs) == len(
                [r for r in para.runs if r.text and r.text.strip()]
            ):
                is_bold_para = True

        if poetry_mode and raw_text_stripped.startswith(("[S]", "[Ch]", "[N]", "[Pic:", "[R]")):
            poetry_mode = False

        if raw_text_stripped.startswith("[S]"):
            in_global_intro = False
            in_section_intro = True
            current_question = None
            chapter_has_question = False
            m = SECTION_RE.search(raw_text_stripped)
            current_section = int(m.group(1)) if m else 0
            current_chapter = 0
            tokens.append({
                "kind": "section_start",
                "section": current_section,
                "chapter": 0,
                "chapter_id": current_chapter,
                "question": None,
                "text": raw_text_stripped,
                "meta": {"block_type": "heading"},
            })
            counts["section_start"] += 1
            transitions.append(("section", current_section))
            continue

        if raw_text_stripped.startswith("[Ch]"):
            in_global_intro = False
            in_section_intro = False
            current_question = None
            chapter_has_question = False
            pending_qnum = None
            m = CHAPTER_RE.search(raw_text_stripped)
            current_chapter = int(m.group(1)) if m else 0
            tokens.append({
                "kind": "chapter_start",
                "section": current_section,
                "chapter": current_chapter,
                "chapter_id": current_chapter,
                "question": None,
                "text": raw_text_stripped,
                "meta": {"block_type": "heading"},
            })
            counts["chapter_start"] += 1
            transitions.append(("chapter", current_chapter))
            continue

        has_blue = False
        question_text_parts = []
        trailing_parts = []
        seen_blue = False

        for run in para.runs:
            if not run.text:
                continue
            rgb = run.font.color.rgb if run.font.color else None
            if _is_blueish(rgb):
                has_blue = True
                seen_blue = True
                question_text_parts.append(run.text)
            elif seen_blue:
                trailing_parts.append(_render_run_with_emphasis(run))
        q_num = forced_qnum

        # Case 1: red question number without blue text → buffer it
        if q_num is not None and not has_blue:
            pending_qnum = q_num
            continue

        # Case 2: blue text without number but a pending question exists → attach it
        if has_blue and q_num is None and pending_qnum is not None:
            q_num = pending_qnum
            pending_qnum = None

        is_question_para = bool(has_blue and q_num is not None)
        if has_blue and q_num is None and os.environ.get("DLB_DEBUG_CHAPTER") == str(current_chapter):
            preview = raw_text_stripped[:80]
            print(f"BLUE_NONQUESTION chapter={current_chapter} raw={preview}")

        if poetry_mode and (
            is_question_para
            or (
                is_bold_para
                and not raw_text_stripped.startswith(("[N]", "[P]", "[Pic:", "[R]"))
                and not RESPONSIVE_RE.search(raw_text_stripped.upper())
            )
        ):
            poetry_mode = False

        if is_bold_para and not is_question_para and not raw_text_stripped.startswith(("[N]", "[P]", "[Pic:", "[R]")) and not RESPONSIVE_RE.search(raw_text_stripped.upper()):
            heading_text = _render_runs_with_emphasis(para)
            if "<strong>" not in heading_text:
                heading_text = f"<strong>{heading_text}</strong>"
            if in_global_intro and current_section == 0 and current_chapter == 0:
                tokens.append({
                    "kind": "heading",
                    "section": 0,
                    "chapter": 0,
                    "chapter_id": current_chapter,
                    "question": None,
                    "text": heading_text,
                    "meta": {"block_type": "heading", "bold": True},
                })
                counts["heading"] += 1
            elif in_section_intro and current_chapter == 0:
                tokens.append({
                    "kind": "heading",
                    "section": current_section,
                    "chapter": 0,
                    "chapter_id": current_chapter,
                    "question": None,
                    "text": heading_text,
                    "meta": {"block_type": "heading", "bold": True},
                })
                counts["heading"] += 1
            else:
                tokens.append({
                    "kind": "heading",
                    "section": current_section,
                    "chapter": current_chapter,
                    "chapter_id": current_chapter,
                    "question": current_question,
                    "text": heading_text,
                    "meta": {"block_type": "heading", "bold": True},
                })
                counts["heading"] += 1
            continue

        if is_question_para and q_num is not None:
            current_question = q_num
            if not question_text_parts:
                fallback = re.sub(r"^\s*\d{1,3}\s*[\.\)]\s*", "", raw_text_stripped)
                fallback = re.sub(r"^\s*\d{1,3}\s+", "", fallback)
                question_text_parts.append(fallback)
            chapter_has_question = True
            question_text = "".join(question_text_parts).strip()
            if os.environ.get("DLB_DEBUG_CHAPTER") == str(current_chapter):
                preview = raw_text_stripped[:80]
                print(
                    f"Q_DETECT chapter={current_chapter} q={q_num} raw={preview}"
                )
            tokens.append({
                "kind": "question",
                "section": current_section,
                "chapter": current_chapter,
                "chapter_id": current_chapter,
                "question": q_num,
                "text": question_text,
                "meta": {},
            })
            counts["question"] += 1
            pending_qnum = None

            trailing = "".join(trailing_parts).strip()
            if not trailing and "?" in question_text:
                parts = question_text.split("?", 1)
                if len(parts) > 1:
                    trailing = parts[1].strip()
            if trailing:
                tokens.append({
                    "kind": "answer",
                    "section": current_section,
                    "chapter": current_chapter,
                    "chapter_id": current_chapter,
                    "question": q_num,
                    "text": trailing,
                    "meta": {"block_type": "answer"},
                })
                counts["answer"] += 1
            continue

        starts_poetry = raw_text_stripped.startswith("[P]")
        if starts_poetry:
            poetry_mode = True
        if poetry_mode:
            poetry_text = text
            if starts_poetry:
                poetry_text = _strip_marker_from_rendered(poetry_text, "[P]")
            tokens.append({
                "kind": "poetry",
                "section": current_section,
                "chapter": current_chapter,
                "chapter_id": current_chapter,
                "question": current_question,
                "text": poetry_text,
                "meta": {"block_type": "poetry"},
            })
            counts["poetry"] += 1
            continue

        normalized = " ".join(raw_text.split())
        upper = normalized.upper()
        starts_with_r = normalized.startswith("[R]")
        if (
            starts_with_r
            or RESPONSIVE_RE.search(upper)
            or upper.startswith("A RESPONSIVE READING")
            or upper.startswith("(A RESPONSIVE READING")
            or upper.startswith("RESPONSIVE READING")
        ):
            content = _render_runs_with_emphasis(para)
            if starts_with_r:
                content = _strip_marker_from_rendered(content, "[R]")
            tokens.append({
                "kind": "responsive",
                "section": current_section,
                "chapter": current_chapter,
                "chapter_id": current_chapter,
                "question": None,
                "text": content,
                "meta": {"block_type": "responsive"},
            })
            counts["responsive"] += 1
            continue

        if raw_text_stripped.startswith("[N]"):
            tokens.append({
                "kind": "note",
                "section": current_section,
                "chapter": current_chapter,
                "chapter_id": current_chapter,
                "question": current_question,
                "text": _strip_marker_from_rendered(text, "[N]"),
                "meta": {"block_type": "note"},
            })
            counts["note"] += 1
            continue

        if raw_text_stripped.startswith("[Pic:"):
            m = PIC_RE.match(raw_text_stripped)
            if m:
                fname = m.group(1).strip()
                tokens.append({
                    "kind": "image",
                    "section": current_section,
                    "chapter": current_chapter,
                    "chapter_id": current_chapter,
                    "question": current_question,
                    "text": f"[Pic:{fname}]",
                    "meta": {"block_type": "image", "image_filename": fname},
                })
                counts["image"] += 1
                continue

        if (
            not chapter_has_question
            and not is_bold_para
            and not raw_text_stripped.startswith(("[S]", "[Ch]", "[P]", "[N]", "[Pic:", "[R]"))
            and not is_question_para
        ):
            tokens.append({
                "kind": "intro",
                "section": current_section,
                "chapter": current_chapter,
                "chapter_id": current_chapter,
                "question": None,
                "text": text,
                "meta": {"block_type": "intro"},
            })
            counts["intro"] += 1
            continue

        # Attach any remaining content to the active question if one exists.
        if current_question is not None:
            tokens.append({
                "kind": "answer",
                "section": current_section,
                "chapter": current_chapter,
                "chapter_id": current_chapter,
                "question": current_question,
                "text": text,
                "meta": {"block_type": "answer"},
            })
            counts["answer"] += 1
        else:
            # Standalone content (chapter/section intro or global prose)
            tokens.append({
                "kind": "intro",
                "section": current_section,
                "chapter": current_chapter,
                "question": None,
                "text": text,
                "meta": {"block_type": "intro"},
            })
            counts["intro"] += 1

    summary = {
        "counts": dict(counts),
        "transitions": transitions,
    }
    return tokens, summary


def _print_summary(summary):
    counts = summary.get("counts", {})
    print("Token counts:")
    for key in sorted(counts.keys()):
        print(f"  {key}: {counts[key]}")
    if "heading" in counts:
        print(f"  heading: {counts['heading']}")
    transitions = summary.get("transitions", [])
    section_nums = [t[1] for t in transitions if t[0] == "section"]
    chapter_nums = [t[1] for t in transitions if t[0] == "chapter"]
    if section_nums:
        print(f"Sections detected: {len(section_nums)}")
    if chapter_nums:
        print(f"Chapters detected: {len(chapter_nums)}")




def main():
    if not os.path.exists(INPUT_DOC):
        print(f"Error: Input document not found at {INPUT_DOC}")
        return
    tokens, summary = classify_docx(INPUT_DOC)
    _print_summary(summary)
    json_path = os.environ.get("DLB_CLASSIFY_JSON", "").strip()
    if json_path:
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(tokens, f, ensure_ascii=True, indent=2)


if __name__ == "__main__":
    main()
