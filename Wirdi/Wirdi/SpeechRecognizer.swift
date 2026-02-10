//
//  SpeechRecognizer.swift
//  Wirdi
//
//

import Foundation
import Speech
import AVFoundation
import IOKit.pwr_mgt

@Observable
class SpeechRecognizer {
    var recognizedCharCount: Int = 0
    var isListening: Bool = false
    var error: String?
    var audioLevels: [CGFloat] = Array(repeating: 0, count: 30)
    var lastSpokenText: String = ""
    var shouldDismiss: Bool = false

    /// True when recent audio levels indicate the user is actively speaking
    var isSpeaking: Bool {
        let recent = audioLevels.suffix(10)
        guard !recent.isEmpty else { return false }
        let avg = recent.reduce(0, +) / CGFloat(recent.count)
        return avg > 0.015
    }

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var sourceText: String = ""
    private var sourceWords: [String] = []
    private var sourceWordOffsets: [Int] = []
    private var normalizedSourceWords: [String] = []
    private var sourceWordIsAnnotation: [Bool] = []
    private var matchStartOffset: Int = 0  // char offset to start matching from
    private var retryCount: Int = 0
    private let maxRetries: Int = 10
    private var configurationChangeObserver: Any?
    private var pendingRestart: DispatchWorkItem?
    private var sleepAssertionID: IOPMAssertionID = 0
    private var backwardJumpPending = false
    private var recentSpokenWords: [String] = []
    private let recentSpokenWordLimit: Int = 80
    private let recentMatchWordCount: Int = 6
    private let localSearchBackWords: Int = 80
    private let localSearchForwardWords: Int = 120
    private let minMatchWords: Int = 3
    private let strongMatchWords: Int = 5
    private let manualJumpWindowWords: Int = 24
    private let manualJumpMaxAttempts: Int = 6
    private let nearForwardWords: Int = 20       // Near-forward window (relaxed match)
    private let sequentialSearchWords: Int = 12  // How far ahead to look for sequential match
    private let sequentialMinWordLength: Int = 3  // Min word length for single-word match beyond 2 words ahead

    private var audioBufferCount: Int = 0
    private var manualJumpPending = false
    private var manualJumpTargetOffset: Int = 0
    private var manualJumpAttempts: Int = 0
    private var matchAttemptsWithoutAdvance: Int = 0
    private let autoAdvanceThreshold: Int = 8

    /// Jump highlight to a specific char offset (e.g. when user taps a word)
    func jumpTo(charOffset: Int) {
        recognizedCharCount = charOffset
        matchStartOffset = charOffset
        retryCount = 0
        manualJumpTargetOffset = charOffset
        manualJumpPending = true
        manualJumpAttempts = 0
        if isListening {
            restartRecognition()
        }
    }

    func start(with text: String) {
        // Clean up any previous session immediately so pending restarts
        // and stale taps are removed before the async auth callback fires.
        cleanupRecognition()

        let collapsed = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        sourceText = collapsed
        rebuildSourceWordCache()
        recognizedCharCount = 0
        matchStartOffset = 0
        retryCount = 0
        error = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.beginRecognition()
                default:
                    self?.error = "Speech recognition not authorized"
                }
            }
        }
    }

    func stop() {
        isListening = false
        allowDisplaySleep()
        cleanupRecognition()
    }

    func forceStop() {
        isListening = false
        allowDisplaySleep()
        sourceText = ""
        retryCount = maxRetries
        cleanupRecognition()
    }

    func resume() {
        retryCount = 0
        matchStartOffset = recognizedCharCount
        shouldDismiss = false
        beginRecognition()
    }

    private func preventDisplaySleep() {
        guard sleepAssertionID == 0 else { return }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Wirdi Quran reading session" as CFString,
            &sleepAssertionID
        )
    }

    private func allowDisplaySleep() {
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }

    private func cleanupRecognition() {
        // Cancel any pending restart to prevent overlapping beginRecognition calls
        pendingRestart?.cancel()
        pendingRestart = nil

        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationChangeObserver = nil
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    /// Coalesces all delayed beginRecognition() calls into a single pending work item.
    /// Any previously scheduled restart is cancelled before the new one is queued.
    private func scheduleBeginRecognition(after delay: TimeInterval) {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRestart = nil
            self.beginRecognition()
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginRecognition() {
        // Ensure clean state
        cleanupRecognition()
        backwardJumpPending = false
        recentSpokenWords.removeAll()
        audioBufferCount = 0
        matchAttemptsWithoutAdvance = 0

        // Create a fresh engine so it picks up the current hardware format.
        // AVAudioEngine caches the device format internally and reset() alone
        // does not reliably flush it after a mic switch.
        audioEngine = AVAudioEngine()

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar"))
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = upcomingContextualStrings()
        recognitionRequest.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Guard against invalid format during device transitions (e.g. mic switch)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            // Retry after a short delay to let the audio system settle
            if retryCount < maxRetries {
                retryCount += 1
                scheduleBeginRecognition(after: 0.3)
            } else {
                error = "Audio input unavailable"
                isListening = false
            }
            return
        }

        // Observe audio configuration changes (e.g. mic switched) to restart gracefully
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.sourceText.isEmpty else { return }
            self.restartRecognition()
        }

        // Belt-and-suspenders: ensure no stale tap exists before installing
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)

            guard let self else { return }
            // Throttle UI updates: dispatch every 5th buffer (~8/sec instead of ~43/sec)
            self.audioBufferCount += 1
            guard self.audioBufferCount % 5 == 0 else { return }

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            let level = CGFloat(min(rms * 5, 1.0))

            DispatchQueue.main.async {
                self.audioLevels.append(level)
                if self.audioLevels.count > 30 {
                    self.audioLevels.removeFirst()
                }
            }
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.retryCount = 0 // Reset on success
                    let transcription = result.bestTranscription
                    let fullText = transcription.formattedString
                    self.lastSpokenText = fullText

                    let allWords = fullText.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    let recent = Array(allWords.suffix(self.recentSpokenWordLimit))
                    // Skip only if the transcript is literally identical to the last one processed
                    if recent == self.recentSpokenWords { return }
                    self.recentSpokenWords = recent
                    self.matchCharacters(recentWords: recent)
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    // If recognitionRequest is nil, cleanup already ran (intentional cancel) — don't retry
                    guard self.recognitionRequest != nil else { return }
                    if self.isListening && !self.shouldDismiss && !self.sourceText.isEmpty && self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        // Advance match offset so the new session matches from current position
                        self.matchStartOffset = self.recognizedCharCount
                        let delay = min(Double(self.retryCount) * 0.5, 1.5)
                        self.scheduleBeginRecognition(after: delay)
                    } else {
                        self.isListening = false
                        self.allowDisplaySleep()
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            preventDisplaySleep()
        } catch {
            // Transient failure after a device switch — retry
            if retryCount < maxRetries {
                retryCount += 1
                scheduleBeginRecognition(after: 0.3)
            } else {
                self.error = "Audio engine failed: \(error.localizedDescription)"
                isListening = false
            }
        }
    }

    private func restartRecognition() {
        // Reset retries so the fresh engine gets a full set of attempts
        retryCount = 0
        isListening = true
        // Longer delay to let the audio system fully settle after a device change
        cleanupRecognition()
        scheduleBeginRecognition(after: 0.5)
    }

    // MARK: - Fuzzy character-level matching

    private func matchCharacters(recentWords: [String]) {
        // If a backward jump was initiated, ignore callbacks until restart completes
        guard !backwardJumpPending else { return }
        guard !sourceWords.isEmpty else { return }

        let recentNormalized = recentWords.suffix(recentMatchWordCount).map {
            Self.normalize($0).filter { $0.isLetter || $0.isNumber }
        }.filter { !$0.isEmpty }
        guard !recentNormalized.isEmpty else { return }

        let currentIndex = wordIndex(at: recognizedCharCount)

        if manualJumpPending {
            let targetIndex = wordIndex(at: manualJumpTargetOffset)
            let start = max(0, targetIndex - manualJumpWindowWords)
            let end = min(sourceWords.count - 1, targetIndex + manualJumpWindowWords)
            if let match = findBestMatch(
                recentWords: recentNormalized,
                searchStart: start,
                searchEnd: end,
                preferIndex: targetIndex,
                minTailWords: minMatchWords
            ) {
                applyMatch(match)
                manualJumpPending = false
                return
            }

            manualJumpAttempts += 1
            if manualJumpAttempts < manualJumpMaxAttempts {
                // Hold position until speech catches up to the tapped word.
                return
            }
            manualJumpPending = false
        }

        // --- Phase 0: Sequential advancement (60% bias toward next word) ---
        // Check if recent speech matches upcoming source words with relaxed
        // requirements (1-2 words). This keeps the highlight advancing smoothly
        // during normal sequential reading without needing a strong multi-word match.
        let seqEnd = min(sourceWords.count - 1, currentIndex + sequentialSearchWords)
        if currentIndex + 1 <= seqEnd {
            if let match = findSequentialMatch(
                recentWords: recentNormalized,
                currentIndex: currentIndex,
                searchEnd: seqEnd
            ) {
                applyMatch(match)
                return
            }
        }

        // --- Full speech matching (40% — fallback for jumps, re-reading, etc.) ---
        // Requires stronger multi-word matches to prevent false positives.
        guard recentNormalized.count >= minMatchWords else { return }

        // 1a) Near-forward search — relaxed word requirement for close matches.
        let nearEnd = min(sourceWords.count - 1, currentIndex + nearForwardWords)
        if let match = findBestMatch(
            recentWords: recentNormalized,
            searchStart: currentIndex,
            searchEnd: nearEnd,
            preferIndex: currentIndex,
            minTailWords: minMatchWords
        ) {
            applyMatch(match)
            return
        }

        // 1b) Far-forward search — requires strong evidence to prevent jumping
        //     to a repeated phrase 30-40+ words ahead.
        let farStart = nearEnd + 1
        let farEnd = min(sourceWords.count - 1, currentIndex + localSearchForwardWords)
        if farStart <= farEnd {
            if let match = findBestMatch(
                recentWords: recentNormalized,
                searchStart: farStart,
                searchEnd: farEnd,
                preferIndex: currentIndex,
                minTailWords: strongMatchWords
            ) {
                applyMatch(match)
                return
            }
        }

        // 2) Then backward (re-reading / went back).
        let backStart = max(0, currentIndex - localSearchBackWords)
        let backEnd = currentIndex
        if let match = findBestMatch(
            recentWords: recentNormalized,
            searchStart: backStart,
            searchEnd: backEnd,
            preferIndex: currentIndex,
            minTailWords: minMatchWords
        ) {
            applyMatch(match)
            return
        }

        // 3) If no local match, allow a stronger global match behind.
        if let match = findBestMatch(
            recentWords: recentNormalized,
            searchStart: 0,
            searchEnd: currentIndex,
            preferIndex: currentIndex,
            minTailWords: strongMatchWords
        ) {
            applyMatch(match)
            return
        }

        // 4) Finally, allow a stronger global match ahead.
        if let match = findBestMatch(
            recentWords: recentNormalized,
            searchStart: currentIndex,
            searchEnd: sourceWords.count - 1,
            preferIndex: currentIndex,
            minTailWords: strongMatchWords
        ) {
            applyMatch(match)
            return
        }

        // No match found — track consecutive failures for auto-advance
        matchAttemptsWithoutAdvance += 1
        if matchAttemptsWithoutAdvance >= autoAdvanceThreshold && isSpeaking {
            autoAdvanceOneWord()
        }
    }

    /// When the highlight is stuck and the user is still speaking, advance to
    /// the next non-annotation word so the session doesn't stall indefinitely.
    private func autoAdvanceOneWord() {
        let currentIndex = wordIndex(at: recognizedCharCount)
        var nextIdx = currentIndex + 1
        while nextIdx < sourceWords.count && sourceWordIsAnnotation[nextIdx] {
            nextIdx += 1
        }
        guard nextIdx < sourceWords.count else { return }
        let nextEnd = sourceWordOffsets[nextIdx] + sourceWords[nextIdx].count
        recognizedCharCount = min(nextEnd, sourceText.count)
        matchStartOffset = recognizedCharCount
        matchAttemptsWithoutAdvance = 0
    }


    private func rebuildSourceWordCache() {
        let words = sourceText.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        sourceWords = words
        normalizedSourceWords = []
        sourceWordOffsets = []
        sourceWordIsAnnotation = []

        var offset = 0
        for word in words {
            sourceWordOffsets.append(offset)
            normalizedSourceWords.append(Self.normalize(word).filter { $0.isLetter || $0.isNumber })
            sourceWordIsAnnotation.append(Self.isAnnotationWord(word))
            offset += word.count + 1
        }
    }

    private func wordIndex(at charOffset: Int) -> Int {
        guard !sourceWordOffsets.isEmpty else { return 0 }
        var idx = 0
        for i in 0..<sourceWordOffsets.count {
            if sourceWordOffsets[i] <= charOffset {
                idx = i
            } else {
                break
            }
        }
        return idx
    }

    private func upcomingContextualStrings() -> [String] {
        let startIdx = wordIndex(at: matchStartOffset)
        let endIdx = min(sourceWords.count, startIdx + 50)
        guard startIdx < endIdx else { return [] }
        return Array(sourceWords[startIdx..<endIdx]).filter { !Self.isAnnotationWord($0) }
    }

    /// Sequential match: check if recently spoken words match the next few upcoming
    /// non-annotation source words. Only considers the immediately next words (not a
    /// wide window) to prevent jumping over unread content when a repeated/similar
    /// word appears further ahead (e.g. الرحمن in both bismillah and verse 3).
    private func findSequentialMatch(
        recentWords: [String],
        currentIndex: Int,
        searchEnd: Int
    ) -> (start: Int, end: Int, tailLen: Int)? {
        // Collect the next few non-annotation word positions only.
        // This prevents skipping real words when a similar word appears far ahead.
        let maxCandidates = 5
        var candidates: [Int] = []
        var idx = currentIndex + 1
        while idx <= searchEnd && candidates.count < maxCandidates {
            if !sourceWordIsAnnotation[idx] && !normalizedSourceWords[idx].isEmpty {
                candidates.append(idx)
            }
            idx += 1
        }
        guard !candidates.isEmpty else { return nil }

        // Try 2-word match at the first candidate position (strongest signal)
        if recentWords.count >= 2, let firstPos = candidates.first {
            let lastTwo = Array(recentWords.suffix(2))
            let tailEnd = min(sourceWords.count - 1, firstPos + 3)
            if let match = matchTail(lastTwo, startIndex: firstPos, searchEnd: tailEnd) {
                return (start: match.start, end: match.end, tailLen: 2)
            }
        }

        // Fall back to single-word match against the candidate positions
        guard let lastWord = recentWords.last, !lastWord.isEmpty else { return nil }

        for (i, srcIdx) in candidates.enumerated() {
            let srcWord = normalizedSourceWords[srcIdx]

            // Beyond the immediate next word, require longer words to
            // avoid false positives on common short words like "the", "a", "is"
            if i > 0 {
                if lastWord.count < sequentialMinWordLength || srcWord.count < sequentialMinWordLength {
                    continue
                }
                // In short surahs, repeated words appear in nearby ayahs
                // (e.g. الرحمن in both ayah 1 and 3 of Al-Fatiha). Cap how
                // far a single-word match can jump so it doesn't skip over
                // an unread ayah; the multi-word matching phases handle
                // larger jumps with stronger evidence.
                if srcIdx - currentIndex > 4 {
                    continue
                }
            }

            let matched: Bool
            if i == 0 {
                // For the immediate next word, allow 2-char words to fuzzy-match
                // (e.g. Arabic particles من، في، لا، ما) with edit distance <= 1.
                if srcWord.count <= 2 && lastWord.count <= 2 && srcWord.count > 0 && lastWord.count > 0 {
                    matched = srcWord == lastWord || editDistance(srcWord, lastWord) <= 1
                } else {
                    matched = srcWord == lastWord || isRelaxedFuzzyMatch(srcWord, lastWord)
                }
            } else {
                matched = srcWord == lastWord || isFuzzyMatch(srcWord, lastWord)
            }
            if matched {
                return (start: srcIdx, end: srcIdx, tailLen: 1)
            }
        }

        return nil
    }

    private func findBestMatch(
        recentWords: [String],
        searchStart: Int,
        searchEnd: Int,
        preferIndex: Int,
        minTailWords: Int
    ) -> (start: Int, end: Int, tailLen: Int)? {
        guard searchStart <= searchEnd else { return nil }
        guard !recentWords.isEmpty else { return nil }

        let maxTail = min(recentWords.count, recentMatchWordCount)
        var bestScore: Int?
        var bestMatch: (start: Int, end: Int, tailLen: Int)?

        for tailLen in stride(from: maxTail, through: minTailWords, by: -1) {
            let tail = Array(recentWords.suffix(tailLen))
            if tailLen < 4 {
                let totalChars = tail.reduce(0) { $0 + $1.count }
                let hasLongWord = tail.contains { $0.count >= 4 }
                if !hasLongWord || totalChars < 8 { continue }
            }

            for start in searchStart...searchEnd {
                if sourceWordIsAnnotation[start] { continue }
                guard let match = matchTail(tail, startIndex: start, searchEnd: searchEnd) else { continue }
                let distance = abs(match.start - preferIndex)
                let score = tailLen * 1000 - distance
                if bestScore == nil || score > bestScore! {
                    bestScore = score
                    bestMatch = (match.start, match.end, tailLen)
                }
            }
        }

        return bestMatch
    }

    private func matchTail(_ tail: [String], startIndex: Int, searchEnd: Int) -> (start: Int, end: Int)? {
        var srcIdx = startIndex
        var firstMatch: Int?

        for spWord in tail {
            while srcIdx <= searchEnd && sourceWordIsAnnotation[srcIdx] {
                srcIdx += 1
            }
            if srcIdx > searchEnd { return nil }

            let srcWord = normalizedSourceWords[srcIdx]
            if srcWord.isEmpty {
                srcIdx += 1
                continue
            }

            if srcWord == spWord || isFuzzyMatch(srcWord, spWord) {
                if firstMatch == nil { firstMatch = srcIdx }
                srcIdx += 1
            } else {
                return nil
            }
        }

        guard let start = firstMatch else { return nil }
        let end = max(start, srcIdx - 1)
        return (start, end)
    }

    private func applyMatch(_ match: (start: Int, end: Int, tailLen: Int)) {
        guard match.end < sourceWords.count else { return }

        // Auto-advance past trailing annotation words (ayah numbers, brackets, etc.)
        // so the highlight doesn't stall on non-readable markers.
        var endIdx = match.end
        while endIdx + 1 < sourceWords.count && sourceWordIsAnnotation[endIdx + 1] {
            endIdx += 1
        }

        let endOffset = sourceWordOffsets[endIdx] + sourceWords[endIdx].count
        if endOffset != recognizedCharCount {
            recognizedCharCount = min(endOffset, sourceText.count)
            matchStartOffset = recognizedCharCount
        }
        matchAttemptsWithoutAdvance = 0
    }




    private static func isAnnotationWord(_ word: String) -> Bool {
        if word.hasPrefix("[") && word.hasSuffix("]") { return true }
        let stripped = word.filter { $0.isLetter || $0.isNumber }
        if stripped.isEmpty { return true }
        // Verse-end markers: words that are only digits (e.g. ١, ١٢٣)
        if stripped.allSatisfy(\.isNumber) { return true }
        return false
    }


    private func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        if a.isEmpty || b.isEmpty { return false }
        // Exact match
        if a == b { return true }
        let shorter = min(a.count, b.count)
        // Very short words (1-2 chars): require exact match only
        // Prevents Arabic particles like من، في from matching inside longer words
        if shorter <= 2 { return false }
        // One starts with the other (phonetic prefix)
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        // One contains the other — only for longer words to avoid false positives
        if shorter >= 4 && (a.contains(b) || b.contains(a)) { return true }
        // Shared prefix >= 60% of shorter word
        let shared = zip(a, b).prefix(while: { $0 == $1 }).count
        if shared >= max(2, shorter * 3 / 5) { return true }
        // Edit distance tolerance
        let dist = editDistance(a, b)
        if shorter <= 4 { return dist <= 1 }
        if shorter <= 8 { return dist <= 2 }
        return dist <= max(a.count, b.count) / 3
    }

    private func isRelaxedFuzzyMatch(_ a: String, _ b: String) -> Bool {
        if isFuzzyMatch(a, b) { return true }
        if a.isEmpty || b.isEmpty { return false }
        let shorter = min(a.count, b.count)
        if shorter <= 2 { return false }
        // Accept 50% shared prefix (vs 60% in standard)
        let shared = zip(a, b).prefix(while: { $0 == $1 }).count
        if shared >= max(2, shorter / 2) { return true }
        // One extra edit distance
        let dist = editDistance(a, b)
        if shorter <= 4 { return dist <= 2 }
        if shorter <= 8 { return dist <= 3 }
        return false
    }

    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                dp[j] = a[i-1] == b[j-1] ? prev : min(prev, dp[j], dp[j-1]) + 1
                prev = temp
            }
        }
        return dp[b.count]
    }

    private static let arabicNormalizationMap: [Character: String] = [
        "أ": "ا",
        "إ": "ا",
        "آ": "ا",
        "ٱ": "ا",
        "ى": "ي",
        "ئ": "ي",
        "ؤ": "و",
        "ة": "ه",
        "ء": ""
    ]

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let stripped = lowered.applyingTransform(.stripDiacritics, reverse: false) ?? lowered
        var result = String()
        result.reserveCapacity(stripped.count)
        for ch in stripped {
            if ch == "ـ" { continue } // tatweel
            if let replacement = arabicNormalizationMap[ch] {
                result.append(contentsOf: replacement)
                continue
            }
            if ch.isLetter || ch.isNumber || ch.isWhitespace {
                result.append(ch)
            }
        }
        return result
    }

}
