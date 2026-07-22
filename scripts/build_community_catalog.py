#!/usr/bin/env python3
"""Build metadata-only catalogue JSON from Sky Music visual-sheet paths."""
# Import deterministic JSON, ID hashing, HTML decoding, and paths.
import hashlib
import html
import json
import sys
from pathlib import Path
# Decode the public GitHub tree response and choose its file list.
tree = json.loads(Path(sys.argv[1]).read_text())["tree"]
# Preserve the public website folder labels without inventing categories.
labels = {"anime": "Anime", "classical": "Classical", "movies": "Movies", "original_players_songs": "Original player songs", "popular": "Popular", "traditional": "Traditional", "videogames": "Video games"}
# Keep only public visual sheet pages beneath a recognised category folder.
paths = [row["path"] for row in tree if row["path"].startswith("songs/") and row["path"].endswith(".html")]
# Convert paths into source-linked metadata without copying a note payload.
songs = []
for path in paths:
    _, folder, filename = path.split("/", 2)
    title = html.unescape(Path(filename).stem.replace("_", " "))
    songs.append({"id": "sheet-" + hashlib.sha256(path.encode()).hexdigest()[:20], "title": title, "arranger": None, "durationSeconds": None, "remoteFile": path, "sourceURL": "https://sky-music.github.io/" + path, "visualSheetURL": "https://sky-music.github.io/" + path, "category": labels[folder]})
# Write a readable app resource containing only public metadata.
Path(sys.argv[2]).write_text(json.dumps({"songs": songs}, ensure_ascii=False, indent=2) + "\n")
