"""Tests for the offline Genshin lyre score player."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


class ValidateScoreTests(unittest.TestCase):
    """Ensure unsafe or malformed score data never reaches the key sender."""

    def test_rejects_a_score_with_an_unknown_key(self):
        """Only the 21 displayed lyre keys are accepted."""
        root = Path(__file__).parents[1]
        source = root / "player" / "GenshinLyrePlayer.swift"
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "player"
            subprocess.run(["swiftc", str(source), "-o", str(executable)], check=True)
            score = Path(temporary_directory) / "bad-score.json"
            score.write_text(json.dumps([{"delayMs": 0, "keys": ["p"]}]))
            result = subprocess.run(
                [str(executable), "--validate-only", str(score)],
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown key: p", result.stderr)

    def test_library_lists_the_source_backed_lyre_songs(self):
        """The native picker must list every finished, source-backed lyre score."""
        root = Path(__file__).parents[1]
        library = json.loads((root / "scores" / "public-domain" / "library.json").read_text())
        self.assertEqual(
            [entry["id"] for entry in library["songs"]],
            [
                "aloha_oe",
                "beautiful_dreamer",
                "sakura_sakura",
                "red_river_valley",
            ],
        )

    def test_every_library_entry_has_a_valid_natural_note_score(self):
        """Every picker option must point at a real score using only lyre keys."""
        root = Path(__file__).parents[1]
        songs = root / "scores" / "public-domain"
        library = json.loads((songs / "library.json").read_text())
        allowed = set("qwertyuasdfghjzxcvbnm")
        for entry in library["songs"]:
            events = json.loads((songs / entry["file"]).read_text())
            self.assertGreater(len(events), 8, entry["id"])
            for event in events:
                self.assertGreaterEqual(event["delayMs"], 0, entry["id"])
                self.assertTrue(set(event["keys"]) <= allowed, entry["id"])

    def test_native_app_exposes_a_song_picker_and_stop_action(self):
        """The desktop app must offer the three-song library and a real stop control."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("NSPopUpButton", source)
        self.assertIn("NSButton(title: \"Stop\"", source)
        self.assertIn("Bundle.main", source)
        self.assertIn("Timing: original 100%", source)

    def test_native_app_retains_its_window_for_the_full_app_lifetime(self):
        """AppKit must not release a locally-created NSWindow after launch."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("private var window: NSWindow?", source)
        self.assertIn("self.window = NSWindow(", source)

    def test_native_midi_engine_contract(self):
        """The dependency-free Swift engine must parse timing, tracks, and chords."""
        root = Path(__file__).parents[1]
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "midi-engine-tests"
            subprocess.run(
                [
                    "swiftc",
                    str(root / "player" / "MidiEngine.swift"),
                    str(root / "tests" / "MidiEngineTests.swift"),
                    "-o",
                    str(executable),
                ],
                check=True,
            )
            result = subprocess.run([str(executable)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MidiEngineTests passed", result.stdout)

    def test_native_app_exposes_the_complete_midi_import_workflow(self):
        """The visible app must wire drag/drop, track choice, mapping, and playback."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("registerForDraggedTypes([.fileURL])", source)
        self.assertIn("Open MIDI…", source)
        self.assertIn("Enabled tracks", source)
        self.assertIn("Strict — skip black keys", source)
        self.assertIn("Snap black keys down", source)
        self.assertIn("Snap black keys up", source)
        self.assertIn("Merge nearby notes", source)
        self.assertIn("play(score:", source)

    def test_imported_scores_can_be_saved_without_copying_private_midi(self):
        """Local persistence must store generated JSON under Application Support only."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        private_docs = (root / "docs" / "PRIVATE_SCORES.md").read_text()
        self.assertIn("final class UserScoreStore", source)
        self.assertIn("custom-library.json", source)
        self.assertIn("Save to Library", source)
        self.assertIn("applicationSupportDirectory", source)
        self.assertIn("original MIDI is never copied", private_docs)

    def test_scroll_document_uses_intrinsic_content_height(self):
        """The importer grid must not stretch rows across a hard-coded scroll document."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("final class FlippedStackView", source)
        self.assertIn("stack.frame.size.height = stack.fittingSize.height", source)
        self.assertIn("grid.setContentHuggingPriority(.required, for: .vertical)", source)
        self.assertNotIn("height: 900", source)


if __name__ == "__main__":
    unittest.main()
