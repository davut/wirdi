//
//  QuranData.swift
//  Wirdi
//
//  Quran data layer: parses word-by-word JSON, reconstructs ayahs,
//  generates reading segments, and tracks reading progress.
//

import Foundation
import AppKit

// MARK: - Raw JSON Model

struct QuranWordEntry: Codable {
    let id: Int
    let surah: String
    let ayah: String
    let word: String
    let location: String
    let text: String
}

// MARK: - Processed Models

struct QuranAyah {
    let surahNumber: Int
    let ayahNumber: Int
    let words: [String]     // all words including verse end marker
    let text: String        // joined with spaces
    let readableWordCount: Int  // excluding verse end marker
}

struct QuranReadingSegment {
    let surahNumber: Int
    let surahName: String
    let startAyah: Int
    let endAyah: Int
    let ayahs: [QuranAyah]
    let displayText: String     // all ayahs joined for overlay display
    let totalReadableWords: Int

    /// Map a character offset within `displayText` back to the ayah it falls in.
    func ayahAt(charOffset: Int) -> Int {
        var offset = 0
        for ayah in ayahs {
            let nextOffset = offset + ayah.text.count + 1  // +1 for joining space
            if charOffset < nextOffset { return ayah.ayahNumber }
            offset = nextOffset
        }
        return ayahs.last?.ayahNumber ?? startAyah
    }
}

// MARK: - Data Manager

class QuranDataManager {
    static let shared = QuranDataManager()

    /// Lightweight ayah counts — populated on first load, used by pickers.
    private var _ayahCounts: [Int: Int] = [:]
    /// Raw grouped entries — kept until a surah is built, then freed per-surah.
    private var _rawGrouped: [Int: [Int: [QuranWordEntry]]] = [:]
    /// Built surahs — populated lazily on demand.
    private var _surahs: [Int: [QuranAyah]] = [:]
    private var _isLoaded = false
    private let lock = NSLock()

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isLoaded
    }

    func loadIfNeeded() {
        lock.lock()
        guard !_isLoaded else { lock.unlock(); return }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: "quran-words", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }

        guard let entries = try? JSONDecoder().decode([String: QuranWordEntry].self, from: data) else { return }

        // Group entries by surah → ayah → words
        var grouped: [Int: [Int: [QuranWordEntry]]] = [:]
        for (_, entry) in entries {
            guard let s = Int(entry.surah), let a = Int(entry.ayah) else { continue }
            grouped[s, default: [:]][a, default: []].append(entry)
        }

        // Extract lightweight ayah counts (114 entries)
        var counts: [Int: Int] = [:]
        for (surahNum, ayahMap) in grouped {
            counts[surahNum] = ayahMap.count
        }

        lock.lock()
        _rawGrouped = grouped
        _ayahCounts = counts
        _isLoaded = true
        lock.unlock()
    }

    /// Build a surah's [QuranAyah] array from raw entries. Must be called under lock.
    private func buildSurah(_ surahNum: Int) -> [QuranAyah]? {
        if let cached = _surahs[surahNum] { return cached }
        guard let ayahMap = _rawGrouped[surahNum] else { return nil }

        var ayahList: [QuranAyah] = []
        for (ayahNum, words) in ayahMap {
            let sortedWords = words.sorted { Int($0.word) ?? 0 < Int($1.word) ?? 0 }
            let wordTexts = sortedWords.map(\.text)
            let text = wordTexts.joined(separator: " ")

            let lastWord = wordTexts.last ?? ""
            let isLastMarker = lastWord.allSatisfy { !$0.isLetter }
            let readableCount = isLastMarker ? max(0, wordTexts.count - 1) : wordTexts.count

            ayahList.append(QuranAyah(
                surahNumber: surahNum,
                ayahNumber: ayahNum,
                words: wordTexts,
                text: text,
                readableWordCount: readableCount
            ))
        }
        let sorted = ayahList.sorted { $0.ayahNumber < $1.ayahNumber }
        _surahs[surahNum] = sorted
        _rawGrouped.removeValue(forKey: surahNum) // free raw entries for this surah
        return sorted
    }

    /// Returns ayah count without triggering data load. Safe to call from view bodies.
    func ayahCount(forSurah surah: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _ayahCounts[surah] ?? 0
    }

    /// Build a reading segment starting from the given position.
    func getReadingSegment(fromSurah: Int, fromAyah: Int, targetWordCount: Int) -> QuranReadingSegment? {
        loadIfNeeded()
        lock.lock()
        let surahAyahs = buildSurah(fromSurah)
        lock.unlock()
        guard let surahAyahs else { return nil }

        var collected: [QuranAyah] = []
        var totalWords = 0

        for ayah in surahAyahs where ayah.ayahNumber >= fromAyah {
            collected.append(ayah)
            totalWords += ayah.readableWordCount
            if totalWords >= targetWordCount { break }
        }

        guard let first = collected.first, let last = collected.last else { return nil }

        let displayText = collected.map(\.text).joined(separator: " ")
        return QuranReadingSegment(
            surahNumber: first.surahNumber,
            surahName: Self.surahName(first.surahNumber),
            startAyah: first.ayahNumber,
            endAyah: last.ayahNumber,
            ayahs: collected,
            displayText: displayText,
            totalReadableWords: totalWords
        )
    }

    /// Compute the next reading position after a segment completes.
    func nextPosition(after segment: QuranReadingSegment) -> (surah: Int, ayah: Int) {
        guard let last = segment.ayahs.last else { return (segment.surahNumber, segment.endAyah) }
        let lastSurah = last.surahNumber
        let lastAyah = last.ayahNumber
        let count = ayahCount(forSurah: lastSurah)

        if lastAyah < count {
            return (lastSurah, lastAyah + 1)
        } else if lastSurah < 114 {
            return (lastSurah + 1, 1)
        } else {
            return (1, 1) // Khatm — wrap to Al-Fatihah
        }
    }

    // MARK: - Surah Names

    static func surahName(_ number: Int) -> String {
        surahNames[number] ?? "سورة \(number)"
    }

    /// Ligature string for the surah-name-v4 font, e.g. "surah001"
    static func surahLigature(_ number: Int) -> String {
        surahLigatures[number] ?? surahName(number)
    }

    /// Font for rendering surah name ligatures
    static let surahNameFont: NSFont = {
        NSFont(name: "surah-name-v4", size: 40) ?? NSFont.systemFont(ofSize: 40)
    }()

    static func surahNameFont(size: CGFloat) -> NSFont {
        NSFont(name: "surah-name-v4", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    private static let surahLigatures: [Int: String] = {
        guard let url = Bundle.main.url(forResource: "ligatures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var result: [Int: String] = [:]
        for (key, value) in dict {
            // Keys are "surah-1", "surah-2", etc.
            if let num = Int(key.replacingOccurrences(of: "surah-", with: "")) {
                result[num] = value
            }
        }
        return result
    }()

    static let surahNames: [Int: String] = [
        1: "الفاتحة", 2: "البقرة", 3: "آل عمران", 4: "النساء", 5: "المائدة",
        6: "الأنعام", 7: "الأعراف", 8: "الأنفال", 9: "التوبة", 10: "يونس",
        11: "هود", 12: "يوسف", 13: "الرعد", 14: "إبراهيم", 15: "الحجر",
        16: "النحل", 17: "الإسراء", 18: "الكهف", 19: "مريم", 20: "طه",
        21: "الأنبياء", 22: "الحج", 23: "المؤمنون", 24: "النور", 25: "الفرقان",
        26: "الشعراء", 27: "النمل", 28: "القصص", 29: "العنكبوت", 30: "الروم",
        31: "لقمان", 32: "السجدة", 33: "الأحزاب", 34: "سبأ", 35: "فاطر",
        36: "يس", 37: "الصافات", 38: "ص", 39: "الزمر", 40: "غافر",
        41: "فصلت", 42: "الشورى", 43: "الزخرف", 44: "الدخان", 45: "الجاثية",
        46: "الأحقاف", 47: "محمد", 48: "الفتح", 49: "الحجرات", 50: "ق",
        51: "الذاريات", 52: "الطور", 53: "النجم", 54: "القمر", 55: "الرحمن",
        56: "الواقعة", 57: "الحديد", 58: "المجادلة", 59: "الحشر", 60: "الممتحنة",
        61: "الصف", 62: "الجمعة", 63: "المنافقون", 64: "التغابن", 65: "الطلاق",
        66: "التحريم", 67: "الملك", 68: "القلم", 69: "الحاقة", 70: "المعارج",
        71: "نوح", 72: "الجن", 73: "المزمل", 74: "المدثر", 75: "القيامة",
        76: "الإنسان", 77: "المرسلات", 78: "النبأ", 79: "النازعات", 80: "عبس",
        81: "التكوير", 82: "الانفطار", 83: "المطففين", 84: "الانشقاق", 85: "البروج",
        86: "الطارق", 87: "الأعلى", 88: "الغاشية", 89: "الفجر", 90: "البلد",
        91: "الشمس", 92: "الليل", 93: "الضحى", 94: "الشرح", 95: "التين",
        96: "العلق", 97: "القدر", 98: "البينة", 99: "الزلزلة", 100: "العاديات",
        101: "القارعة", 102: "التكاثر", 103: "العصر", 104: "الهمزة", 105: "الفيل",
        106: "قريش", 107: "الماعون", 108: "الكوثر", 109: "الكافرون", 110: "النصر",
        111: "المسد", 112: "الإخلاص", 113: "الفلق", 114: "الناس"
    ]
}
