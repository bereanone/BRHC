import sqlite3
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DB = (BASE_DIR / "assets" / "databases" / "brhc.db").resolve()
IMAGES_DIR = (BASE_DIR / "Images").resolve()

assert IMAGES_DIR.exists() and IMAGES_DIR.is_dir(), f"Images folder not found: {IMAGES_DIR}"

conn = sqlite3.connect(DB)
cur = conn.cursor()

print(f"📂 Reading images from: {IMAGES_DIR}")
print(f"🗄️  Writing to database: {DB}")

# Clear existing images to ensure clean rebuild
cur.execute("DELETE FROM images")
cur.execute(
    """
    CREATE TABLE IF NOT EXISTS images (
        image_id INTEGER PRIMARY KEY AUTOINCREMENT,
        filename TEXT,
        description TEXT,
        image_blob BLOB
    )
    """
)

# Verify images table schema
cur.execute("PRAGMA table_info(images)")
cols = {row[1] for row in cur.fetchall()}
required = {"image_id", "filename", "description", "image_blob"}
if not required.issubset(cols):
    raise RuntimeError("images table schema mismatch; aborting import")

select_sql = """
SELECT image_id FROM images
WHERE LOWER(filename) = LOWER(?)
LIMIT 1
"""

insert_sql = """
INSERT OR IGNORE INTO images (filename, description, image_blob)
VALUES (?, ?, ?)
"""

scanned = 0
inserted = 0
skipped = 0

for img_path in sorted(IMAGES_DIR.iterdir()):
    if not img_path.is_file():
        continue

    if img_path.suffix.lower() not in [".png", ".jpg", ".jpeg"]:
        continue

    scanned += 1

    row = cur.execute(select_sql, (img_path.name,)).fetchone()
    if row is not None:
        skipped += 1
        print(f"⏭️  Skipped existing image: {img_path.name}")
        continue

    with open(img_path, "rb") as f:
        blob = f.read()

    desc = f"Imported image: {img_path.name}"

    cur.execute(insert_sql, (img_path.name, desc, blob))
    inserted += 1
    print(f"🖼️  Imported NEW image: {img_path.name}")

conn.commit()
conn.close()

print("✅ Image import complete")
print(f"Total files scanned: {scanned}")
print(f"New images inserted: {inserted}")
print(f"Existing images skipped: {skipped}")
