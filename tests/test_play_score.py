"""Tests for the offline Genshin lyre score player."""

import json
import hashlib
import plistlib
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
        self.assertEqual([entry["id"] for entry in library["songs"]], ["aloha_oe"])

    def test_aloha_score_remains_unchanged(self):
        """Library cleanup must never alter the proven Aloha arrangement."""
        root = Path(__file__).parents[1]
        score = root / "scores" / "public-domain" / "aloha_oe_full_2m24s_lyre.json"
        self.assertEqual(len(json.loads(score.read_text())), 506)
        self.assertEqual(
            hashlib.sha256(score.read_bytes()).hexdigest(),
            "8226314106d2914858017c4d8cae44e977af6ef6c54e54962f6d1ddd111e7117",
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
        self.assertIn("actionTitle = isActive ? \"Stop\" : \"Play\"", source)
        self.assertIn("Bundle.main", source)
        self.assertIn("Timing: original 100%", source)

    def test_native_app_blocks_silent_playback_without_accessibility(self):
        """Playback must explain missing permission instead of dropping every key silently."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("AXIsProcessTrustedWithOptions", source)
        self.assertIn("Accessibility permission is required", source)

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

    def test_community_library_contract(self):
        """Community responses must convert safely while retaining attribution and cache boundaries."""
        root = Path(__file__).parents[1]
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "community-library-tests"
            subprocess.run(
                [
                    "swiftc",
                    str(root / "player" / "MidiEngine.swift"),
                    str(root / "player" / "CommunityLibrary.swift"),
                    str(root / "tests" / "CommunityLibraryTests.swift"),
                    "-o",
                    str(executable),
                ],
                check=True,
            )
            result = subprocess.run([str(executable)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CommunityLibraryTests passed", result.stdout)

    def test_visual_sheet_exporter_matches_legacy_table_layout(self):
        """Legacy Sky Music pages must use the same table root as the source exporter."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "VisualSheetDownloader.swift").read_text()
        self.assertIn("const cell = table.children[0];", source)
        self.assertNotIn("table.children[0]?.children[0]", source)

    def test_lyre_preview_planner_contract(self):
        """Listen preview must preserve score timing and map the three keyboard rows."""
        root = Path(__file__).parents[1]
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "lyre-preview-tests"
            subprocess.run([
                "swiftc", str(root / "player" / "MidiEngine.swift"),
                str(root / "player" / "LyrePreviewPlayer.swift"),
                str(root / "tests" / "LyrePreviewPlayerTests.swift"),
                "-o", str(executable), "-framework", "AVFoundation",
            ], check=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("LyrePreviewPlayerTests passed", result.stdout)

    def test_community_catalog_contains_metadata_without_note_payloads(self):
        """The repository may identify community work but must not redistribute its notes."""
        root = Path(__file__).parents[1]
        catalog_path = root / "scores" / "community" / "catalog.json"
        catalog_text = catalog_path.read_text()
        catalog = json.loads(catalog_text)
        self.assertGreaterEqual(len(catalog["songs"]), 200)
        self.assertNotIn("songNotes", catalog_text)
        for entry in catalog["songs"]:
            self.assertTrue(entry["id"])
            self.assertTrue(entry["title"])
            self.assertTrue(entry["remoteFile"])
            self.assertTrue(entry["sourceURL"].startswith("https://"))
            self.assertTrue(entry["visualSheetURL"].startswith("https://sky-music.github.io/songs/"))
            self.assertTrue(entry["category"])

    def test_native_app_exposes_the_complete_midi_import_workflow(self):
        """The visible app must wire drag/drop, track choice, mapping, and playback."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("registerForDraggedTypes([.fileURL])", source)
        self.assertIn("Open Score…", source)
        self.assertIn('"txt", "json"', source)
        self.assertIn("loadSkyMusicSheet", source)
        self.assertIn("Enabled tracks", source)
        self.assertIn("Strict — skip black keys", source)
        self.assertIn("Snap black keys down", source)
        self.assertIn("Snap black keys up", source)
        self.assertIn("Merge nearby notes", source)
        self.assertIn("Timing: maximum 200%", source)
        self.assertIn("play(score:", source)

    def test_native_app_exposes_smart_mapping_and_personal_library_controls(self):
        """The visible app must default to Smart and expose favourites plus safe clearing."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("Smart — key-aware", source)
        self.assertIn("toggleFavorite", source)
        self.assertIn("Search My Library", source)
        self.assertIn("filterLibrarySongs", source)
        self.assertNotIn("Set Saved Speed", source)
        self.assertIn("Clear Imported Library…", source)
        self.assertIn("NSAlert", source)
        self.assertIn("userScoreStore.clear()", source)
        self.assertIn("detectedKey", source)
        self.assertIn("removeLibrarySong", source)
        self.assertIn('"Delete"', source)
        self.assertIn("listenImported", source)
        self.assertIn('"Listen"', source)

    def test_native_app_separates_community_library_and_import_destinations(self):
        """A native sidebar must replace the crowded single-page workbench."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("NSSplitView", source)
        self.assertIn(".sourceList", source)
        self.assertIn('"Community Collection"', source)
        self.assertIn('"My Library"', source)
        self.assertIn('"Import MIDI"', source)
        self.assertIn("contentContainer", source)
        self.assertIn("rootView.leadingAnchor.constraint(equalTo: windowHost.leadingAnchor)", source)
        self.assertIn("rootView.trailingAnchor.constraint(equalTo: windowHost.trailingAnchor)", source)
        self.assertIn("splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor)", source)
        self.assertIn("splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor)", source)
        self.assertIn("contentContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 560)", source)
        self.assertIn("showDestination", source)
        self.assertIn("makePersistentFooter", source)

    def test_community_screen_exposes_attribution_download_and_source_actions(self):
        """Community music must remain attributed, remote, and visibly distinct."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("CommunityScoreStore", source)
        self.assertIn("URLSession.shared.dataTask", source)
        self.assertIn("communityVisibleLimit", source)
        self.assertIn('"Load more"', source)
        self.assertIn("communityListenAction", source)
        self.assertIn("communityCategoryPicker", source)
        self.assertIn("VisualSheetDownloader", source)
        self.assertIn("libraryListenAction", source)
        self.assertNotIn('NSButton(title: "Stop", target: self, action: #selector(stopPlayback))', source)
        self.assertIn("creditLine", source)
        self.assertIn('"Open Source"', source)
        self.assertIn("NSWorkspace.shared.open", source)
        self.assertIn("community-catalog", source)

    def test_import_screen_hides_advanced_mapping_until_requested(self):
        """Technical MIDI controls should not dominate the default import screen."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn('"Mapping settings"', source)
        self.assertIn("advancedMappingStack.isHidden = false", source)
        self.assertIn("communityMoreAction", source)
        self.assertIn("systemRed", source)
        self.assertIn('"Preview — 5 second focus time"', source)
        self.assertIn('"Save to My Library"', source)

    def test_imported_scores_can_be_saved_without_copying_private_midi(self):
        """Local persistence must store generated JSON under Application Support only."""
        root = Path(__file__).parents[1]
        app_source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        store_source = (root / "player" / "UserScoreStore.swift").read_text()
        private_docs = (root / "docs" / "PRIVATE_SCORES.md").read_text()
        self.assertNotIn("final class UserScoreStore", app_source)
        self.assertIn("final class UserScoreStore", store_source)
        self.assertIn("custom-library.json", store_source)
        self.assertIn("Save to My Library", app_source)
        self.assertIn("applicationSupportDirectory", store_source)
        self.assertIn("original MIDI is never copied", private_docs)

    def test_user_score_store_contract(self):
        """Favourites and clearing must persist inside an isolated injected root."""
        root = Path(__file__).parents[1]
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "store-tests"
            subprocess.run(
                [
                    "swiftc",
                    str(root / "player" / "MidiEngine.swift"),
                    str(root / "player" / "UserScoreStore.swift"),
                    str(root / "tests" / "UserScoreStoreTests.swift"),
                    "-o",
                    str(executable),
                ],
                check=True,
            )
            result = subprocess.run([str(executable)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("UserScoreStoreTests passed", result.stdout)

    def test_favorite_store_contract(self):
        """Shared favourites must persist across public and community card namespaces."""
        root = Path(__file__).parents[1]
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "favorite-store-tests"
            subprocess.run(
                [
                    "swiftc",
                    str(root / "player" / "FavoriteStore.swift"),
                    str(root / "tests" / "FavoriteStoreTests.swift"),
                    "-o",
                    str(executable),
                ],
                check=True,
            )
            result = subprocess.run([str(executable)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("FavoriteStoreTests passed", result.stdout)

    def test_scroll_document_uses_intrinsic_content_height(self):
        """The importer grid must not stretch rows across a hard-coded scroll document."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("final class FlippedStackView", source)
        self.assertIn("stack.frame.size.height = stack.fittingSize.height", source)
        self.assertIn("grid.setContentHuggingPriority(.required, for: .vertical)", source)
        self.assertNotIn("height: 900", source)

    def test_sidebar_pages_remove_the_divider_and_track_the_available_width(self):
        """The sidebar must not draw a dark rule or clip a page to a fixed document width."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("final class BorderlessSplitView: NSSplitView", source)
        self.assertIn("override var dividerThickness: CGFloat { 0 }", source)
        self.assertNotIn("splitView.dividerStyle = .thin", source)
        self.assertIn("final class ResponsivePageScrollView", source)
        self.assertIn("documentView.frame.size.width = contentView.bounds.width", source)
        self.assertNotIn("stack.frame = NSRect(x: 0, y: 0, width: 680, height: 0)", source)
        self.assertNotIn("card.widthAnchor.constraint(equalToConstant: 620)", source)
        self.assertNotIn("songPicker.widthAnchor.constraint(equalToConstant: 500)", source)
        self.assertNotIn("communitySearchField.widthAnchor.constraint(equalToConstant: 420)", source)
        self.assertIn("widthAnchor.constraint(equalTo: stack.widthAnchor", source)
        self.assertIn("window.titlebarSeparatorStyle = .none", source)
        self.assertIn("action.widthAnchor.constraint(equalToConstant: 92)", source)
        self.assertIn("source.widthAnchor.constraint(equalToConstant: 140)", source)
        self.assertIn("title.lineBreakMode = .byTruncatingTail", source)
        self.assertIn("details.lineBreakMode = .byTruncatingTail", source)

    def test_card_pages_expose_favourites_source_discovery_and_row_stop_actions(self):
        """Both music pages must share hearts, stable rails, and active-row Stop controls."""
        root = Path(__file__).parents[1]
        source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
        self.assertIn("Browse all Sky Music sheets", source)
        self.assertIn("https://sky-music.github.io/", source)
        self.assertIn("private let libraryRowsStack = NSStackView()", source)
        self.assertIn("private func rebuildLibraryRows()", source)
        self.assertIn('let actionTitle = isActive ? "Stop"', source)
        self.assertIn("player.onPlaybackChange", source)
        self.assertIn('NSButton(title: "♥"', source)
        self.assertNotIn("advancedMappingDisclosure.setContentCompressionResistancePriority(.required, for: .horizontal)", source)
        self.assertIn("makeImportCard", source)

    def test_build_binds_the_stable_bundle_identity(self):
        """Rebuilds must retain one Accessibility identity instead of linker-signing each binary."""
        root = Path(__file__).parents[1]
        subprocess.run([str(root / "scripts" / "build_app.sh")], check=True, capture_output=True, text=True)
        app = root / "build" / "Teyvat Virtuoso.app"
        result = subprocess.run(
            ["codesign", "-d", "--verbose=4", str(app)],
            check=True,
            capture_output=True,
            text=True,
        )
        signature = result.stdout + result.stderr
        self.assertIn("Identifier=com.philippsyrov.teyvat-virtuoso", signature)
        self.assertIn("Info.plist entries=", signature)
        with (app / "Contents" / "Info.plist").open("rb") as plist_file:
            metadata = plistlib.load(plist_file)
        self.assertEqual(metadata.get("CFBundleIconFile"), "AppIcon")
        self.assertTrue((app / "Contents" / "Resources" / "AppIcon.icns").is_file())

    def test_project_keeps_the_supplied_lyre_icon_artwork(self):
        """The reproducible icon source must stay beside the compiled macOS icon."""
        root = Path(__file__).parents[1]
        self.assertTrue((root / "assets" / "AppIcon-Paimon-Lyre.jpeg").is_file())


if __name__ == "__main__":
    unittest.main()
