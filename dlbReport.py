import sqlite3
import os

DB_PATH = "assets/databases/brhc.db"

def scalar(cur, sql):
    cur.execute(sql)
    row = cur.fetchone()
    return row[0] if row else None

def count(cur, sql):
    return scalar(cur, f"SELECT COUNT(*) FROM ({sql})")

def run_verification():
    print("=== dlbFix FINAL DIAGNOSTIC RUN ===")
    print("DB:", os.path.abspath(DB_PATH))

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()

    print("\n[DB CHECK]")
    cur.execute("PRAGMA database_list;")
    for r in cur.fetchall():
        print(" ->", r)

    print("\n[TABLE CHECK]")
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
    tables = [r[0] for r in cur.fetchall()]
    for t in tables:
        print(" ->", t)

    print("\n[COUNTS]")
    questions = scalar(cur, "SELECT COUNT(*) FROM questions")
    blocks = scalar(cur, "SELECT COUNT(*) FROM answer_blocks")
    print(" Questions:", questions)
    print(" Answer blocks:", blocks)

    print("\n[ORPHAN CHECK]")
    orphan_blocks = scalar(cur, """
        SELECT COUNT(*)
        FROM answer_blocks ab
        LEFT JOIN questions q ON q.id = ab.question_id
        WHERE q.id IS NULL
    """)
    print(" Orphan blocks:", orphan_blocks)

    print("\n[CHAPTER ATTACHMENT CHECK]")
    cur.execute("""
        SELECT q.chapter_number, COUNT(ab.id)
        FROM questions q
        LEFT JOIN answer_blocks ab ON ab.question_id = q.id
        GROUP BY q.chapter_number
        ORDER BY q.chapter_number
        LIMIT 10
    """)
    rows = cur.fetchall()
    if rows:
        for chap, cnt in rows:
            print(f" Chapter {chap}: {cnt} blocks")
    else:
        print(" NONE")

    print("\n[HEADING BLOCK CHECK]")
    heading_count = scalar(cur, """
        SELECT COUNT(*)
        FROM answer_blocks
        WHERE block_type='heading'
    """)
    print(" Heading blocks:", heading_count)

    print("\n[POETRY NORMALIZATION CHECK]")
    cur.execute("""
        SELECT id,
               length(content) AS len,
               instr(content, char(10)) AS has_newline
        FROM answer_blocks
        WHERE block_type='poetry'
        LIMIT 20
    """)
    poetry = cur.fetchall()
    if not poetry:
        print(" No poetry blocks found")
    else:
        for pid, ln, nl in poetry:
            print(f" id={pid} len={ln} newline={bool(nl)}")

    print("\n[GLOBAL INTRO ANCHOR CHECK]")
    global_anchor = scalar(cur, """
        SELECT COUNT(*)
        FROM questions
        WHERE section_number=0
          AND chapter_number=0
          AND question_number=0
    """)
    print(" Global intro anchor questions:", global_anchor)

    print("\n[RESPONSIVE BLOCK CHECK]")
    responsive_blocks = scalar(cur, """
        SELECT COUNT(*)
        FROM answer_blocks
        WHERE block_type='responsive'
    """)
    print(" Responsive blocks:", responsive_blocks)

    print("\n[SAMPLE BLOCK PREVIEW]")
    cur.execute("""
        SELECT ab.id, ab.block_type, substr(ab.content,1,120)
        FROM answer_blocks ab
        LIMIT 10
    """)
    for r in cur.fetchall():
        print(" ->", r)

    con.close()
    print("\n=== END OF DIAGNOSTIC RUN ===")

if __name__ == "__main__":
    run_verification()