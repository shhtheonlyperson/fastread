// FastReadTokenizerStats — score the live RSVPEngine tokenizer against
// the human-annotated gold corpus at Tests/Fixtures/rsvp-gold-corpus.tsv.
//
// What it prints:
//   1. Boundary precision / recall / F1 vs the gold (the only objective
//      quality number for RSVP chunking).
//   2. Five health stats about chunk *shape* — mean length, % singletons,
//      % long, length variance, function-word orphan rate — to flag
//      "the chunks are technically correct but feel arrhythmic".
//   3. Per-row diff for the 10 worst-scoring rows so we can eyeball what
//      the tokenizer is getting wrong.
//
// Edit the corpus's `ideal-chunks` column to fix your label, rerun. That's
// the feedback loop.
//
//   swift run FastReadTokenizerStats Tests/Fixtures/rsvp-gold-corpus.tsv

import FastReadCore
import Foundation

@main
struct Main {
    static func main() {
        let path = CommandLine.arguments.dropFirst().first
            ?? "Tests/Fixtures/rsvp-gold-corpus.tsv"
        let url = URL(fileURLWithPath: path)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            fputs("❌ couldn't read \(path)\n", stderr)
            exit(1)
        }

        var rows: [(id: String, input: String, gold: [String])] = []
        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let id = String(parts[0])
            let input = String(parts[1])
            let gold = parts[2].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            rows.append((id, input, gold))
        }
        print("Loaded \(rows.count) rows from \(path)\n")

        var sumP = 0.0, sumR = 0.0, sumF = 0.0
        var perRowScores: [(id: String, input: String, gold: [String], actual: [String], f1: Double)] = []
        var allActualChunks: [String] = []

        for row in rows {
            let actual = RSVPEngine.tokenize(row.input).map { stripTrailingPunct($0) }
            let goldClean = row.gold.map { stripTrailingPunct($0) }
            let (p, r, f) = boundaryF1(input: row.input, gold: goldClean, actual: actual)
            sumP += p; sumR += r; sumF += f
            perRowScores.append((row.id, row.input, row.gold, actual, f))
            allActualChunks.append(contentsOf: actual)
        }

        let n = Double(rows.count)
        print("=== Boundary score (current tokenizer vs gold) ===")
        print(String(format: "  precision: %.3f", sumP / n))
        print(String(format: "  recall:    %.3f", sumR / n))
        print(String(format: "  F1:        %.3f", sumF / n))
        print()

        print("=== Chunk-shape health (current tokenizer output across the corpus) ===")
        let stats = chunkStats(allActualChunks)
        print(String(format: "  mean chunk length:    %.2f chars  %@",
            stats.meanLen,
            verdict(stats.meanLen, ideal: 2.5...3.0)))
        print(String(format: "  %% singletons:         %5.1f%%      %@",
            stats.pctSingletons * 100,
            verdict(stats.pctSingletons * 100, max: 15)))
        print(String(format: "  %% long (4+ CJK):      %5.1f%%      %@",
            stats.pctLong * 100,
            verdict(stats.pctLong * 100, max: 10)))
        print(String(format: "  length variance:      %.2f       (lower = smoother rhythm)",
            stats.lenVariance))
        print(String(format: "  function-word orphans: %4.1f%%      %@",
            stats.fnWordOrphans * 100,
            verdict(stats.fnWordOrphans * 100, max: 5)))
        print()

        print("=== 10 worst-scoring rows (where to look first) ===")
        let worst = perRowScores.sorted { $0.f1 < $1.f1 }.prefix(10)
        for row in worst {
            print("[\(row.id)] F1=\(String(format: "%.2f", row.f1))  \(row.input)")
            print("  gold:   \(row.gold.joined(separator: " | "))")
            print("  actual: \(row.actual.joined(separator: " | "))")
        }
    }

    // ---- Boundary scoring -----------------------------------------------

    static func boundaryF1(input: String, gold: [String], actual: [String]) -> (Double, Double, Double) {
        let goldSet = internalBoundaries(of: gold, in: input)
        let actualSet = internalBoundaries(of: actual, in: input)
        if goldSet.isEmpty && actualSet.isEmpty { return (1, 1, 1) }
        let tp = goldSet.intersection(actualSet).count
        let p = actualSet.isEmpty ? 0 : Double(tp) / Double(actualSet.count)
        let r = goldSet.isEmpty ? 0 : Double(tp) / Double(goldSet.count)
        let f = (p + r == 0) ? 0 : 2 * p * r / (p + r)
        return (p, r, f)
    }

    /// Returns the set of internal cumulative-character-count boundaries
    /// implied by a chunk sequence. End-of-string boundary is excluded so
    /// it doesn't trivially count as a correct match.
    static func internalBoundaries(of chunks: [String], in source: String) -> Set<Int> {
        var positions = Set<Int>()
        var running = 0
        let sourceCount = source.unicodeScalars.count
        for chunk in chunks.dropLast() {
            running += chunk.unicodeScalars.count
            if running > 0 && running < sourceCount {
                positions.insert(running)
            }
        }
        return positions
    }

    /// Compare against gold ignoring trailing CJK / ASCII punctuation, so
    /// that "閱讀，" vs "閱讀" doesn't get scored as a different chunk.
    static func stripTrailingPunct(_ s: String) -> String {
        var chars = Array(s)
        while let last = chars.last, isPunctuation(last) {
            chars.removeLast()
        }
        return String(chars)
    }

    static func isPunctuation(_ c: Character) -> Bool {
        c.unicodeScalars.contains { scalar in
            (0x3000...0x303f).contains(scalar.value) ||
            (0xff00...0xffef).contains(scalar.value) ||
            [".", ",", "!", "?", ";", ":"].contains(c)
        }
    }

    // ---- Chunk-shape stats ---------------------------------------------

    struct ChunkStats {
        var meanLen: Double = 0
        var pctSingletons: Double = 0
        var pctLong: Double = 0
        var lenVariance: Double = 0
        var fnWordOrphans: Double = 0
    }

    static func chunkStats(_ chunks: [String]) -> ChunkStats {
        // Limit to chunks containing CJK characters — Latin tokens aren't
        // the thing we want to optimise here.
        let cjkChunks = chunks.filter { $0.contains(where: isCJK) }
        guard !cjkChunks.isEmpty else { return ChunkStats() }
        let lens = cjkChunks.map { $0.unicodeScalars.filter(isCJKScalar).count }
        let mean = Double(lens.reduce(0, +)) / Double(lens.count)
        let variance = lens.reduce(0.0) { acc, l in
            acc + pow(Double(l) - mean, 2)
        } / Double(lens.count)
        let singletons = lens.filter { $0 == 1 }.count
        let longs = lens.filter { $0 >= 4 }.count
        // Function-word orphans: 1-char chunks that are common particles.
        let particles: Set<Character> = ["的", "了", "是", "在", "和", "與", "及", "或", "也", "又", "而", "就", "都", "很", "更", "之", "其", "於", "為", "被", "把", "向", "從", "由", "對", "跟", "與"]
        let orphans = cjkChunks.filter { chunk in
            let cjkLen = chunk.unicodeScalars.filter(isCJKScalar).count
            return cjkLen == 1 && particles.contains(chunk.first ?? " ")
        }.count
        var stats = ChunkStats()
        stats.meanLen = mean
        stats.pctSingletons = Double(singletons) / Double(lens.count)
        stats.pctLong = Double(longs) / Double(lens.count)
        stats.lenVariance = variance
        stats.fnWordOrphans = Double(orphans) / Double(lens.count)
        return stats
    }

    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains(where: isCJKScalar)
    }

    static func isCJKScalar(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x3400...0x4dbf).contains(v) ||
               (0x4e00...0x9fff).contains(v) ||
               (0xf900...0xfaff).contains(v)
    }

    // ---- Verdict formatting --------------------------------------------

    static func verdict(_ value: Double, ideal: ClosedRange<Double>) -> String {
        if ideal.contains(value) { return "✅ in target [\(ideal.lowerBound)..<\(ideal.upperBound)]" }
        return "⚠️ target [\(ideal.lowerBound)..<\(ideal.upperBound)]"
    }

    static func verdict(_ value: Double, max: Double) -> String {
        if value <= max { return "✅ ≤\(max)%" }
        return "⚠️ target ≤\(max)%"
    }
}
