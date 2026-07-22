#!/usr/bin/env python3
"""Build metadata-only Sky Music catalogue JSON from its public index."""
# Import standard JSON parsing and deterministic hashing.
import hashlib
import json
import sys
from pathlib import Path
# Read explicit source and destination paths from the command line.
source_path = Path(sys.argv[1])
destination_path = Path(sys.argv[2])
# Decode only public title/file metadata, never score payloads.
source_rows = json.loads(source_path.read_text())
# Convert each filename into a safe stable identity.
songs = [{
    "id": "sky-" + hashlib.sha256(row["file"].encode()).hexdigest()[:20],
    "title": row["name"],
    "arranger": None,
    "durationSeconds": None,
    "remoteFile": row["file"],
    "sourceURL": "https://sky-music.herokuapp.com/songLibrary.html?download=true",
} for row in source_rows]
# Write only the generated metadata resource in readable Unicode JSON.
destination_path.write_text(json.dumps({"songs": songs}, ensure_ascii=False, indent=2) + "\n")
