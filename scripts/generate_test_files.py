import os
import random
from pathlib import Path

OUT_DIR = Path("test_files")
OUT_DIR.mkdir(exist_ok=True)

SSNS = ["123-45-6789", "999-99-9999"]
CARDS = ["4111 1111 1111 1111", "5555-5555-5555-4444"]
EMAILS = ["alice@example.com", "bob@test.com"]

for i in range(50):
    content = f"File {i}\n"
    if i % 10 == 0:
        content += random.choice(SSNS) + "\n"
    if i % 7 == 0:
        content += random.choice(CARDS) + "\n"
    if i % 5 == 0:
        content += random.choice(EMAILS) + "\n"

    (OUT_DIR / f"sample_{i}.txt").write_text(content)
