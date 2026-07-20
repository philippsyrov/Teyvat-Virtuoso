"""Rank MIDI files for a faithful, source-timed three-row Genshin lyre arrangement."""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import mido


# The Genshin lyre only exposes the seven white-key pitch classes in three rows.
NATURAL_CLASSES = {0, 2, 4, 5, 7, 9, 11}
# Examine enough global transpositions to bring ordinary MIDI arrangements into range.
SHIFT_OPTIONS = range(-6, 7)


@dataclass
class TrackReport:
    """Keep the facts needed to choose source roles rather than guessing from a song title."""

    index: int
    name: str
    notes: list[int]
    first_tick: int
    chord_onsets: int

    @property
    def note_count(self) -> int:
        """Return the number of audible, non-drum note onsets."""
        return len(self.notes)

    @property
    def range_text(self) -> str:
        """Return a compact source pitch range for the human review report."""
        return f"{min(self.notes)}-{max(self.notes)}" if self.notes else "-"


def natural_fit(notes: list[int], shift: int) -> float:
    """Measure how much of a track survives one global key change without chromatic edits."""
    if not notes:
        return 0.0
    return sum((note + shift) % 12 in NATURAL_CLASSES for note in notes) / len(notes)


def best_shift(notes: list[int]) -> tuple[int, float]:
    """Select the transposition with the most unmodified natural notes."""
    return max(((shift, natural_fit(notes, shift)) for shift in SHIFT_OPTIONS), key=lambda item: item[1])


def read_track(index: int, track: mido.MidiTrack) -> TrackReport | None:
    """Read a MIDI track and retain original onsets for chord-density inspection."""
    # MIDI delta times are local to each track, so rebuild its absolute tick positions.
    absolute_tick = 0
    # Keep all audible pitched events and intentionally ignore the drum channel.
    notes: list[int] = []
    # Count note onsets which share a tick as intended chords, not artificial repetition.
    onset_counts: Counter[int] = Counter()
    # Use the standard track-name meta event where the source supplied one.
    name = "unnamed"
    for message in track:
        # Advance into the track's absolute timing domain before inspecting the event.
        absolute_tick += message.time
        # Save a readable source name without requiring a particular MIDI authoring app.
        if message.type == "track_name" and message.name.strip():
            name = message.name.strip()
        # Keep only audible note starts from melodic/instrument tracks.
        if message.type == "note_on" and message.velocity > 0 and message.channel != 9:
            notes.append(message.note)
            onset_counts[absolute_tick] += 1
    # Do not report empty conductor or metadata tracks as musical candidates.
    if not notes:
        return None
    # Count only genuine multi-note onsets; this is the safe MIDI equivalent of a chord.
    chord_onsets = sum(count > 1 for count in onset_counts.values())
    # Keep the first onset so tracks can be ranked for likely lead usage later.
    first_tick = min(onset_counts)
    return TrackReport(index, name, notes, first_tick, chord_onsets)


def recommendation(reports: list[TrackReport], global_shift: int, duration: float) -> str:
    """Give a conservative next step; a high fit alone never promises a good arrangement."""
    # Find the densest source material to avoid mistaking a short vocal cue for a full score.
    note_total = sum(report.note_count for report in reports)
    # Calculate the share that will map directly after one common key shift.
    all_notes = [note for report in reports for note in report.notes]
    fit = natural_fit(all_notes, global_shift)
    # Require real length, enough notes, and strong natural fit before green-lighting conversion.
    if duration >= 50 and note_total >= 180 and fit >= 0.94:
        return "strong candidate: preserve source timing and keep its separate tracks as roles"
    # A short or sparse file may still contain a recognisable hook, but needs listening first.
    if fit >= 0.90:
        return "melody candidate only: audition the selected track before arranging"
    # Do not force badly chromatic music through a white-key-only instrument.
    return "skip for lyre: too many notes would need chromatic changes"


def inspect(source: Path) -> None:
    """Print one human-readable preflight report for a user-supplied MIDI file."""
    # Parse the source before making any claim about its playability.
    midi = mido.MidiFile(source)
    # Extract only musically populated tracks.
    reports = [report for index, track in enumerate(midi.tracks) if (report := read_track(index, track))]
    # Merge notes only for the global fit calculation; roles remain separate in the report.
    all_notes = [note for report in reports for note in report.notes]
    # Select one global shift so bass, accompaniment, and melody remain harmonically aligned.
    shift, fit = best_shift(all_notes)
    # Print a stable header suitable for saving or pasting into the songbook later.
    print(f"\n{source.name}")
    print(f"  duration: {midi.length:.1f}s | musical tracks: {len(reports)} | notes: {len(all_notes)}")
    print(f"  best shared shift: {shift:+d} semitones | natural-note fit: {fit:.1%}")
    print(f"  verdict: {recommendation(reports, shift, midi.length)}")
    # Detail each track because a melody can be good while the accompaniment is unsuitable.
    for report in reports:
        # Measure the track with the same shared shift and also its independent best case.
        shared_fit = natural_fit(report.notes, shift)
        track_shift, track_fit = best_shift(report.notes)
        # Describe actual source chords for a better "Aloha-style" layering signal.
        chord_text = f", {report.chord_onsets} true chord onsets" if report.chord_onsets else ""
        print(
            f"  track {report.index} ({report.name!r}): {report.note_count} notes, range {report.range_text}, "
            f"shared fit {shared_fit:.1%}, own best {track_shift:+d}/{track_fit:.1%}{chord_text}"
        )


# Let the tool accept several downloaded MIDI files in one honest comparison pass.
parser = argparse.ArgumentParser(description=__doc__)
# Require one or more MIDI paths; no invisible default folder means no accidental scans.
parser.add_argument("sources", nargs="+", type=Path, help="one or more .mid/.midi files")
# Parse the user-selected files before opening them.
args = parser.parse_args()
# Inspect each source independently so results cannot be mixed between songs.
for source_path in args.sources:
    inspect(source_path)
