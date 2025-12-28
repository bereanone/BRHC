import sqlite3
from pathlib import Path
import re

DB_PATH = "brhc.db"
IMAGE_DIR = Path("Images")

conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

pattern = re.compile(r"BRHC(\d+)-(\d+)\.(png|jpg|jpeg)", re.IGNORECASE)

for img in sorted(IMAGE_DIR.iterdir()):
    if not img.is_file():
        continue

    m = pattern.match(img.name)
    if not m:
        print(f"Skipping (name not recognized): {img.name}")
        continue

    chapter_number = int(m.group(1))
    question_number = int(m.group(2))

    with open(img, "rb") as f:
        blob = f.read()

    cur.execute("""
        INSERT INTO brhc_images
        (image_name, chapter_number, question_number, image_blob)
        VALUES (?, ?, ?, ?)
    """, (img.name, chapter_number, question_number, blob))

    print(f"Imported {img.name} → Chapter {chapter_number}, Q{question_number}")

conn.commit()
conn.close()

print("All images imported.")