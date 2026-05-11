// ChunkShaper — post-pass over RSVPEngine's raw tokenization that
// reshapes the chunk stream from "linguistically segmented" to
// "rhythmically readable" for RSVP. Three deterministic passes,
// scored against Tests/Fixtures/rsvp-gold-corpus.tsv (run with
// `swift run FastReadTokenizerStats` to see the F1 delta).
//
// Pass 1 — mergeCrossScriptUnits:
//   Latin digit run + immediately-following 1–2 CJK measure word
//   becomes one chunk. "5" + "個月" → "5個月". Picks up "100公斤",
//   "25 度", "10年", etc. across the script boundary that the
//   splitByScript step intentionally created upstream.
//
// Pass 2 — glueFunctionParticles:
//   Single-CJK-char particles like 的 / 了 / 而 / 之 are arrhythmic
//   when flashed alone. Glue them to the prescribed neighbor
//   direction-dependent on the particle role:
//     • aspect + sentence-final: backward  (了 著 過 矣 之 哉)
//     • everything else:         forward   (的 是 在 跟 從 對 …)
//   Caps merged chunk at 4 CJK chars so we don't trade one rhythm
//   problem for another.
//
// Pass 3 — coalesceSingleCharRuns:
//   Three or more adjacent single-CJK-char chunks usually mean ICU
//   didn't recognise that span at all — probably a proper noun
//   (人名 / 地名), a classical / archaic compound, or a brand the
//   dictionary doesn't carry. Group them into rhythm-friendly 2–3
//   char clusters (the size table in `groupSizes`). This is what
//   converts `黃 | 士 | 旗 | 去吃飯` into `黃士旗 | 去吃飯`.

import Foundation

enum ChunkShaper {
    static func shape(_ tokens: [String]) -> [String] {
        var result = mergeCrossScriptUnits(tokens)
        result = mergePrepDigitNoun(result)
        // Coalesce BEFORE particles: otherwise 的's shorter-side rule
        // looks at single-Han stragglers (倫 from 周杰倫) instead of
        // the real modifier (周杰倫).
        result = coalesceSingleCharRuns(result)
        result = glueFunctionParticles(result)
        result = absorbStraySingletons(result)
        return result
    }

    /// Preposition + Latin-digit run + multi-Han noun → one chunk.
    /// Captures address / building / room-number patterns where the
    /// preposition modifies a numbered place: 在|101|大樓 → 在101大樓.
    /// Deliberately skipped when the noun is a single-Han measure word
    /// (mergeCrossScriptUnits already handled e.g. 100|公斤) — the rule
    /// is "prep + number + ≥2-char noun", which leaves 在2025年 as
    /// `在 | 2025年` so the prep flashes alone like the corpus prefers.
    private static let prepositionsForCompound: Set<Character> = [
        "在", "從", "到", "向", "於",
    ]

    private static func mergePrepDigitNoun(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let cur = tokens[i]
            if cur.count == 1,
               let c = cur.first,
               prepositionsForCompound.contains(c),
               i + 2 < tokens.count,
               isDigitRun(tokens[i + 1]),
               cjkCount(tokens[i + 2]) >= 2 {
                result.append(cur + tokens[i + 1] + tokens[i + 2])
                i += 3
                continue
            }
            result.append(cur)
            i += 1
        }
        return result
    }

    // MARK: - Pass 1: cross-script number + measure word

    /// CJK measure words / units common enough to glue to a preceding
    /// digit run. Kept short on purpose — false positives here are
    /// worse than missed glues, because anything wrongly merged shows
    /// up as a too-long chunk and we'll see it in the corpus.
    private static let measureWords: Set<String> = [
        "個", "位", "件", "種", "名", "次", "回", "張", "把", "條", "場", "份",
        "年", "月", "日", "時", "分", "秒", "週", "季", "點", "天",
        "小時", "分鐘", "秒鐘",
        "公斤", "公克", "公尺", "公里", "公分", "公升",
        "元", "塊", "毛", "億", "萬",
        "度",
        "個月", "個人", "歲",
    ]

    private static func mergeCrossScriptUnits(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let cur = tokens[i]
            if isDigitRun(cur), i + 1 < tokens.count, measureWords.contains(tokens[i + 1]) {
                result.append(cur + tokens[i + 1])
                i += 2
                continue
            }
            result.append(cur)
            i += 1
        }
        return result
    }

    private static func isDigitRun(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        for c in s {
            guard c.isASCII else { return false }
            if c.isNumber || c == "." || c == "," { continue }
            return false
        }
        return true
    }

    // MARK: - Pass 2: function-word particle gluing

    /// Particles whose semantic anchor is on the previous token: aspect
    /// markers, classical clause-final particles, modern sentence-final
    /// particles. Flash naturally as the tail of the chunk before.
    /// 而 lives here because in 四言 verse it's most often the second
    /// half of a beat (學而 | 時習之); modern uses ('從容而堅定') also
    /// read naturally trailing.
    private static let particlesBackward: Set<Character> = [
        "了", "著", "過",                                 // aspect
        "之", "矣", "哉", "焉", "乎", "而",                 // classical
        "嗎", "呢", "吧", "啊", "喔", "耶", "呀", "嘛", "呵",  // sentence-final
    ]

    /// Particles whose semantic anchor is on the next token: structural
    /// 的, conjunctions, prepositions, copula 是, and the common
    /// degree/aspect adverbs that everyone learns to chunk forward.
    /// 跟/和/與 are NOT here — they routinely sit between two NPs that
    /// ICU has already split into singletons, and forward-gluing them
    /// would steal the first character of the next NP (我|跟|王|小明
    /// → 跟王 |…). Run coalescing handles them instead.
    private static let particlesForward: Set<Character> = [
        "在", "從", "對", "向", "把", "被", "給",    // prepositions
        "及", "或",                                  // conjunctions
        "是", "為",                                  // copula
        "也", "又", "都", "還", "才", "就", "便",    // adverbs
        "很", "更", "最", "太",                      // degree
        "不", "沒", "未", "別",                      // negation
        "新", "舊",                                   // common content modifiers
    ]

    /// 的 is a special case: it joins the *shorter* side of the noun
    /// phrase it sits between. Gold examples from the corpus:
    ///   • 周杰倫(3) 的 新歌(2)        → 周杰倫 | 的新歌  (forward)
    ///   • 信義區(3) 的 新光三越(4)    → 信義區的 | 新光三越 (backward)
    ///   • 中華民國(4) 的 總統府(3)    → 中華民國 | 的總統府 (forward)
    ///   • 你(1) 的 幫忙(2)           → 你的 | 幫忙 (backward)
    ///   • 好(1) 的 沒問題(3)         → 好的 | 沒問題 (backward)
    /// Tie → forward (only one row in the corpus is a tie and either
    /// direction reads OK).
    private static let possessiveDe: Character = "的"

    private static let maxMergedCJK = 4

    private static func glueFunctionParticles(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let cur = tokens[i]
            if let particle = singleCJKParticle(cur) {
                let leftLen = cjkCount(result.last ?? "")
                let rightLen = i + 1 < tokens.count ? cjkCount(tokens[i + 1]) : 0

                // 的: shorter-side wins. Tie → backward (好的|沒問題,
                // not 好|的沒問題). Falls back to whichever side has
                // room if the preferred side is full.
                if particle == possessiveDe {
                    let preferBackward = (leftLen <= rightLen) && leftLen >= 1
                    if preferBackward, leftLen + 1 <= maxMergedCJK {
                        result[result.count - 1] = result.last! + cur
                        i += 1
                        continue
                    }
                    if rightLen >= 1, rightLen + 1 <= maxMergedCJK {
                        result.append(cur + tokens[i + 1])
                        i += 2
                        continue
                    }
                    if leftLen >= 1, leftLen + 1 <= maxMergedCJK {
                        result[result.count - 1] = result.last! + cur
                        i += 1
                        continue
                    }
                    result.append(cur)
                    i += 1
                    continue
                }

                if particlesBackward.contains(particle),
                   leftLen >= 1,
                   leftLen + 1 <= maxMergedCJK {
                    result[result.count - 1] = result.last! + cur
                    i += 1
                    continue
                }
                // Forward-glue only into a *multi-char* next chunk; the
                // common failure pattern is particles snatching the
                // first single-Han of a name (跟+王, 從+台, 對+她…).
                if particlesForward.contains(particle),
                   rightLen >= 2,
                   rightLen + 1 <= maxMergedCJK {
                    result.append(cur + tokens[i + 1])
                    i += 2
                    continue
                }
            }
            result.append(cur)
            i += 1
        }
        return result
    }

    private static func singleCJKParticle(_ chunk: String) -> Character? {
        // Allow trailing punctuation — "了，" still gets glued backward.
        let cjk = chunk.filter(isHanCharacter)
        guard cjk.count == 1, let particle = cjk.first else { return nil }
        return particle
    }

    private static func cjkCount(_ chunk: String) -> Int {
        chunk.filter(isHanCharacter).count
    }

    // MARK: - Pass 3: coalesce runs of single CJK chunks

    /// Walk the token stream looking for runs of 3+ adjacent single-Han
    /// chunks. ICU produces those runs when its dictionary doesn't know
    /// the span — usually a proper noun (黃士旗), a classical compound
    /// (道可道), or a brand (麥當勞). Group them into 2–3 char chunks.
    ///
    /// When a 4-long run is followed by a multi-char chunk that has
    /// room (≤2 CJK chars), peel the last char off the run and merge
    /// it forward into that chunk. That turns `黃|士|旗|去|吃飯` into
    /// `黃士旗 | 去吃飯` instead of `黃士 | 旗去 | 吃飯` — the name +
    /// VP rhythm the gold corpus actually prefers.
    /// Pronouns most likely to lead a run of singletons that the user
    /// wants split as `pronoun-V | rest` rather than `pronoun-V-V`.
    /// e.g., 你來看一下 → 你來 | 看一下 (gold) instead of 你來看 | 一下.
    private static let pronouns: Set<Character> = [
        "我", "你", "他", "她", "它", "您", "咱",
    ]

    private static func coalesceSingleCharRuns(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            var j = i
            while j < tokens.count,
                  isPureSingleHan(tokens[j]),
                  !isAnyParticle(tokens[j]) {
                j += 1
            }
            let runLen = j - i
            if runLen >= 3 {
                let nextHasRoom = j < tokens.count
                    && cjkCount(tokens[j]) > 0
                    && cjkCount(tokens[j]) <= 2
                // A pronoun ANYWHERE in the run is a strong signal that
                // the span isn't a single noun-like compound (黃士旗 /
                // 道可道) — so peel the last char forward to break the
                // implied S+V or V+pronoun+V rhythm. Examples:
                //   你來看 + 一下      → 你來 | 看一下
                //   我跟王 + 小明      → 我跟 | 王小明
                //   問我懂 + 了        → 問我 | 懂了
                let runHasPronoun = (i..<j).contains { idx in
                    tokens[idx].first.map { pronouns.contains($0) } ?? false
                }

                if runLen == 3, runHasPronoun, nextHasRoom {
                    // Pronoun-led: 你來看 + 一下 → 你來 | 看一下.
                    result.append(tokens[i..<(i + 2)].joined())
                    result.append(tokens[i + 2] + tokens[j])
                    i = j + 1
                    continue
                }
                if runLen == 4, nextHasRoom {
                    // Name-led 4 + VP: 黃|士|旗|去 + 吃飯 → 黃士旗 | 去吃飯.
                    result.append(tokens[i..<(i + 3)].joined())
                    result.append(tokens[i + 3] + tokens[j])
                    i = j + 1
                    continue
                }
                if runLen == 5, nextHasRoom, cjkCount(tokens[j]) == 1 {
                    result.append(tokens[i..<(i + 3)].joined())
                    result.append(tokens[i + 3] + tokens[i + 4] + tokens[j])
                    i = j + 1
                    continue
                }

                var offset = i
                for size in groupSizes(runLen) {
                    result.append(tokens[offset..<offset + size].joined())
                    offset += size
                }
                i = j
            } else if runLen == 2 {
                // Merge a 2-singleton run only when the following chunk
                // isn't already a multi-Han phrase that should "claim"
                // the second singleton. This preserves `我 | 去吃飯了`
                // (next = 吃飯了, multi → leave 我 and 去 alone) while
                // still fixing `我用 | VS Code` (next = Latin → merge).
                let nextNotMultiCJK = j >= tokens.count
                    || cjkCount(tokens[j]) < 2
                if nextNotMultiCJK {
                    result.append(tokens[i..<j].joined())
                    i = j
                } else {
                    result.append(tokens[i])
                    i += 1
                }
            } else {
                result.append(tokens[i])
                i += 1
            }
        }
        return result
    }

    // MARK: - Pass 4: absorb leftover stray single-char chunks

    /// After particle gluing and run coalescing some single-Han chunks
    /// still float — usually a content-word singleton between two
    /// multi-char neighbours. Try BACKWARD first (target ≤3 CJK chars
    /// to keep tight rhythm). Fall through to FORWARD with a slightly
    /// looser cap of 4 so V + V-aspect compounds like `去 + 吃飯了`
    /// can merge into `去吃飯了` without losing the rhythm. Skip
    /// forward-glue into a single-Han neighbour — that's the case ICU
    /// most often misclassifies (兩個 single Han = a name we don't want
    /// to grow into).
    private static func absorbStraySingletons(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let cur = tokens[i]
            guard cur.count == 1, cur.allSatisfy(isHanCharacter) else {
                result.append(cur)
                i += 1
                continue
            }
            // Backward into multi-char prev (cap 3).
            if let last = result.last,
               cjkCount(last) >= 2,
               cjkCount(last) + 1 <= 3 {
                result[result.count - 1] = last + cur
                i += 1
                continue
            }
            // Forward into multi-char next (cap 4). Skip single-Han
            // next so we don't fuse two separately-recognised words
            // ICU split apart (likely a name).
            if i + 1 < tokens.count,
               cjkCount(tokens[i + 1]) >= 2,
               cjkCount(tokens[i + 1]) + 1 <= 4 {
                result.append(cur + tokens[i + 1])
                i += 2
                continue
            }
            // Stand alone (the gold corpus does want pronouns + lone
            // verbs to flash alone sometimes — `我 | 去吃飯了`).
            result.append(cur)
            i += 1
        }
        return result
    }

    private static func isPureSingleHan(_ chunk: String) -> Bool {
        // Strict: exactly one character, and that character is Han.
        // Aspect-marker chunks like "了，" already include punct so
        // they don't satisfy this and won't get pulled into a run.
        chunk.count == 1 && chunk.allSatisfy(isHanCharacter)
    }

    private static func isAnyParticle(_ chunk: String) -> Bool {
        guard let c = chunk.first, chunk.count == 1 else { return false }
        return c == possessiveDe
            || particlesForward.contains(c)
            || particlesBackward.contains(c)
    }

    /// Prefer threes, never trail with a one, never produce a chunk
    /// over `maxMergedCJK`. This is the rhythm rulebook for unknown
    /// proper nouns and classical-Chinese spans.
    static func groupSizes(_ n: Int) -> [Int] {
        switch n {
        case 0, 1, 2: return Array(repeating: 1, count: n)
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [2, 3]
        case 6: return [3, 3]
        case 7: return [3, 2, 2]
        case 8: return [3, 3, 2]
        case 9: return [3, 3, 3]
        default:
            var sizes: [Int] = []
            var remaining = n
            while remaining > 4 {
                sizes.append(3)
                remaining -= 3
            }
            sizes += groupSizes(remaining)
            return sizes
        }
    }

    // MARK: - Han detection (kept local so this file doesn't depend on
    // RSVPEngine's private helpers).

    private static func isHanCharacter(_ c: Character) -> Bool {
        c.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x3400...0x4dbf).contains(v) ||  // CJK Ext A
                   (0x4e00...0x9fff).contains(v) ||  // CJK
                   (0xf900...0xfaff).contains(v)     // CJK Compatibility
        }
    }
}
