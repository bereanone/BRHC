#!/usr/bin/env bash
set -e

echo "==============================="
echo " BRHC FULL REBUILD PIPELINE"
echo "==============================="

# 1. Activate virtual environment
echo "→ Activating virtual environment"
source .venv/bin/activate

# 2. Sanity check: database must be writable
echo "→ Verifying database is writable"
python - <<EOF
import sqlite3
db="assets/databases/brhc.db"
conn=sqlite3.connect(db)
conn.execute("CREATE TABLE IF NOT EXISTS __write_test (id INTEGER)")
conn.execute("DROP TABLE __write_test")
conn.commit()
conn.close()
print("  ✔ Database writable")
EOF

# 3. Import / refresh images (safe, idempotent)
echo "→ Importing images"
python dlbImportImages.py

# 4. Classify DOCX (NO DB writes, pure analysis)
echo "→ Classifying DOCX structure"
python dlbDocxClassify.py

# 5. Insert DOCX blocks (DESTRUCTIVE, authoritative)
echo "→ Rebuilding answer_blocks and anchors"
python dlbDocxInsertBlocks.py

# 6. Optional: run legacy wrapper if still needed
# (only keep this if dlbDocxImport.py does something extra)
# echo "→ Running legacy import wrapper"
# python dlbDocxImport.py --import

# 7. Run full integrity diagnostics
echo "→ Running database integrity checks"
python dlbReport.py

# 8. Wipe Flutter sandbox so app reloads fresh DB
echo "→ Wiping Flutter sandbox"
python dlbWipeBRHCSandbox.py

echo "==============================="
echo " BRHC REBUILD COMPLETE"
echo "==============================="