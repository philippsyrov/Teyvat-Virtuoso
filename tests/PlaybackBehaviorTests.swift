import Foundation

func playbackExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data(("FAIL: \(message)\n").utf8))
        exit(1)
    }
}

@main
struct PlaybackBehaviorTests {
    static func main() {
        let document = MidiDocument(
            tracks: [MidiTrackInfo(index: 0, name: "Piano", noteCount: 3, minimumNote: 60, maximumNote: 62, chordOnsets: 0)],
            durationMs: 20,
            bestTranspose: 5,
            ticksPerQuarter: 1_000,
            notes: [
                MidiNoteOn(trackIndex: 0, tick: 0, note: 60),
                MidiNoteOn(trackIndex: 0, tick: 20, note: 62),
                MidiNoteOn(trackIndex: 0, tick: 40, note: 61),
            ],
            tempos: [MidiTempoChange(tick: 0, microsecondsPerQuarter: 500_000)]
        )
        let raw = ImportDefaults.raw
        let rawScore = document.makeScore(options: raw.options(enabledTrackIndexes: [0]))
        playbackExpect(rawScore == [
            ImportedScoreEvent(delayMs: 0, keys: ["a"]),
            ImportedScoreEvent(delayMs: 10, keys: ["s"]),
        ], "raw import must keep source key, timing, and separate onsets without inventing a black-key note")
        playbackExpect(raw.playbackSpeed == 1.0, "raw import must use original 100% timing")

        let ready = ImportedPreviewControl(activePlaybackID: nil)
        playbackExpect(ready.title == "Preview — 5 second focus time" && !ready.shouldStop, "idle imported Preview must be ready to start")
        let active = ImportedPreviewControl(activePlaybackID: "import:preview")
        playbackExpect(active.title == "Stop" && active.shouldStop, "active imported Preview must expose Stop")

        let belowRange = SavedSpeedControl(playbackSpeed: 0.86)
        playbackExpect(belowRange.playbackSpeed == 0.90 && belowRange.percentageLabel == "90%", "saved speed controls must clamp below-range values to 90%")
        let betweenSteps = SavedSpeedControl(playbackSpeed: 1.73)
        playbackExpect(betweenSteps.playbackSpeed == 1.75 && betweenSteps.percentageLabel == "175%", "saved speed controls must snap dragging to readable 5% steps")
        let aboveRange = SavedSpeedControl(playbackSpeed: 2.40)
        playbackExpect(aboveRange.playbackSpeed == 2.00 && aboveRange.percentageLabel == "200%", "saved speed controls must clamp above-range values to 200%")

        let targets = PlaybackTimeline.targetSeconds(
            for: [ImportedScoreEvent(delayMs: 100, keys: ["a"]), ImportedScoreEvent(delayMs: 200, keys: ["s"])],
            speed: 2.0
        )
        playbackExpect(targets == [0.05, 0.15], "absolute targets must scale source onsets without adding the key-hold duration")
        var waitedTargets: [Double] = []
        var playedKeys: [[String]] = []
        let completed = PlaybackTimeline.perform(
            score: [ImportedScoreEvent(delayMs: 100, keys: ["a"]), ImportedScoreEvent(delayMs: 200, keys: ["s"])],
            speed: 2.0,
            waitUntil: { target in waitedTargets.append(target); return true },
            playChord: { keys in playedKeys.append(keys) }
        )
        playbackExpect(completed && waitedTargets == [0.05, 0.15], "playback must wait against absolute source targets")
        playbackExpect(playedKeys == [["a"], ["s"]], "playback must emit every score chord in order")
        print("PlaybackBehaviorTests passed")
    }
}
