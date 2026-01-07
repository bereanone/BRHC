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

cur.execute(
    """
    CREATE TABLE IF NOT EXISTS brhc_images (
        image_id INTEGER PRIMARY KEY AUTOINCREMENT,
        filename TEXT NOT NULL,
        description TEXT,
        image_blob BLOB NOT NULL
    )
    """
)

select_sql = """
SELECT image_id FROM brhc_images
WHERE LOWER(filename) = LOWER(?)
LIMIT 1
"""

insert_sql = """
INSERT INTO brhc_images (filename, description, image_blob)
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
