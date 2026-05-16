# Chinese tokenization for RSVP — what changed and why

How we got from a fixed-bigram chopper to a measurable, deterministic, rhythm-aware tokenizer scoring 0.847 boundary F1 against a human-annotated corpus.

## TL;DR

| Phase | Boundary F1 | Mean chunk | Singletons | Notes |
|---|---|---|---|---|
| Fixed bigram (legacy JS) | — | 2.0 | low but wrong | Split every word at char-2 regardless of word boundaries |
| `NLTokenizer` alone | 0.679 | 1.53 | 55% | Linguistically correct, rhythmically awful |
| + ChunkShaper v1 | 0.828 | 2.43 | 13% | Rhythm-aware grouping |
| + leading-punct + cross-script preposition | **0.847** | 2.43 | 13% | Current production tokenizer |

The journey is documented commit-by-commit:
- `a380713` — Replace bigram with `NLTokenizer` + script split + user dictionary
- `65a32de` — Reframe goal as rhythmic chunking, add ChunkShaper
- `e0e36c9` — Leading-punctuation preservation + cross-script preposition rule
- `c7328ea` — Port to Kotlin so Android matches

## The reframe

Linguistically correct word segmentation is the **wrong** target for RSVP.

RSVP flashes one chunk at a time at 200–1500 words per minute. The eye has 40–200 ms to register each chunk and the brain has even less. What works is **rhythmic chunking**: 2–4 character clusters that the eye-brain pipeline can recognise as a single Gestalt — *not* the dictionary word boundaries that NLTokenizer / ICU / jieba all converge on.

Concrete example. `黃士旗去吃飯`:

| Tokenizer | Output | Why it's wrong |
|---|---|---|
| Bigram | `黃士 / 旗去 / 吃飯` | Splits the name across chunks (`旗去` is meaningless) |
| ICU / NLTokenizer | `黃 / 士 / 旗 / 去 / 吃飯` | Linguistically defensible (the name is OOV) but visually arrhythmic — five flashes for a 6-char sentence |
| jieba (default zh-CN dict) | `黃 / 士旗 / 去 / 吃 / 飯` | Worse — wrong split inside the name |
| Our shaper | `黃士旗 / 去吃飯` | Subject + predicate, two beats, name intact ✅ |

Same idea drives 80% of the rules.

## How we measure

Two artefacts in the repo make the loop deterministic.

### 1. Gold corpus

`Tests/Fixtures/rsvp-gold-corpus.tsv` — 50 hand-annotated Traditional-Chinese sentences. Each row:

```
id    input    ideal-chunks-separated-by-|
```

The `ideal-chunks` column is **the user's RSVP-readability judgment**, not a linguistic answer. Categories cover:

- People names (`黃士旗`, `周杰倫`, `蔡英文`)
- Place names (`陽明山`, `信義區`, `中華民國`)
- Brands (`星巴克`, `麥當勞`, `7-Eleven`)
- Cross-script units (`100公斤`, `25°C`, `12.5%`)
- Code / URLs (`fetchUser()`, `RFC-7231`, `https://…`)
- Quotes & punctuation
- Classical / literary Chinese (`道可道`, `學而時習之`)
- Daily / conversational
- Modern compounds (`元宇宙`, `區塊鏈`)

The user edits this file when a chunk looks wrong; the new label becomes the new spec.

### 2. Stats CLI

```bash
swift run FastReadTokenizerStats                     # score against gold
swift run FastReadTokenizerStats --epub path.epub    # health on real prose
```

The tool prints six numbers and the 10 worst-scoring rows:

```
Boundary precision / recall / F1   ← against gold, the canonical regression
mean chunk length                  ← target 2.5–3.0
% singletons                       ← target ≤ 15%
% long (4+ CJK)                    ← target ≤ 10%
length variance                    ← lower = smoother rhythm
function-word orphans              ← target ≤ 5%
```

Worst-10 is the next-action queue. Every gain in this codebase came from staring at it.

## The pipeline

Five deterministic passes after script-split + ICU and the user dictionary. All in `Sources/FastReadCore/ChunkShaper.swift` with a byte-equivalent port at `android-spike/app/src/main/java/.../core/ChunkShaper.kt`.

```
script-split         ←  CJK / Latin segments
   ↓
NLTokenizer/ICU      ←  per-segment word boundaries
   ↓
user dictionary      ←  custom proper-noun merges
   ↓
ChunkShaper.shape:
  ① mergeCrossScriptUnits      digit + CJK measure word (5公里, 100公斤)
  ② mergePrepDigitNoun         在 + 101 + 大樓 → 在101大樓
  ③ coalesceSingleCharRuns     3+ adjacent single-Han → 2-3 char clusters
  ④ glueFunctionParticles      的 / 了 / 在 / 是 / etc.
  ⑤ absorbStraySingletons      remaining 1-Han chunks → multi-char neighbour
   ↓
final chunks
```

### Pass 1 — `mergeCrossScriptUnits`

Latin digit run followed immediately by a CJK measure word fuses into one chunk. The measure-word set is intentionally small (~50 entries) — false positives here produce too-long chunks that show up in `% long`.

```
Input  ["重量", "100", "公斤"]
Output ["重量", "100公斤"]
```

### Pass 2 — `mergePrepDigitNoun`

Preposition + Latin digit + ≥2-char Han noun. Captures the address / building / room-number pattern. Deliberately skipped when the trailing chunk is a measure-word-led number+unit (`在 + 2025年` stays as `在 | 2025年` so the prep flashes alone).

```
在 + 101 + 大樓     → 在101大樓
在 + 2025 + 年      → 在 | 2025年    (年 is a measure word, handled by pass 1)
```

### Pass 3 — `coalesceSingleCharRuns`

Where most of the F1 lift came from. Three or more adjacent single-Han chunks with no particle in between usually means ICU didn't recognise that span at all — a proper noun, classical compound, or brand the dictionary doesn't carry.

Heuristics, in order of precedence:

- **k=3 with a pronoun anywhere in the run + next has room** → peel the last char forward. Captures `你來看 + 一下 → 你來 | 看一下` and `我跟王 + 小明 → 我跟 | 王小明`.
- **k=4 + multi-char next** → group first three as name, peel the 4th forward. `黃 | 士 | 旗 | 去 + 吃飯 → 黃士旗 | 去吃飯`.
- **k=5 + multi-char single-Han next** → `[3, 1+next]` arrangement.
- **k=2 only if next isn't multi-Han** → keeps `我 | 去吃飯了` from collapsing to `我去 | 吃飯了`; allows `我用 + VS Code` to merge `我用`.
- **everything else** → `groupSizes(n)` table (prefers 3s, never trails with 1, never produces a chunk over 4 CJK chars).

### Pass 4 — `glueFunctionParticles`

Directional gluing keyed on particle role.

**Backward** (`了 著 過 之 矣 哉 焉 乎 而 嗎 呢 吧 啊 …`) — aspect markers + sentence-final + classical clause-final. These are tail-of-chunk particles.

**Forward** (`在 從 對 向 把 被 給 跟 和 是 為 也 又 都 還 才 就 便 很 更 最 太 不 沒 未 別 新 舊 …`) — prepositions, copula, adverbs, common modifiers. Forward only into a ≥2-CJK-char next chunk; otherwise leave alone. The narrow-forward rule prevents particles from snatching the first single-Han of a name (`跟 + 王 → 跟王` taking the start of 王小明).

**`的` is special** — shorter-side wins. Tie → backward. Captures:

| Pattern | Direction | Result |
|---|---|---|
| 周杰倫(3) 的 新歌(2) | left ≥ right → forward | `周杰倫 \| 的新歌` |
| 信義區(3) 的 新光三越(4) | left < right → backward | `信義區的 \| 新光三越` |
| 中華民國(4) 的 總統府(3) | left > right → forward | `中華民國 \| 的總統府` |
| 你(1) 的 幫忙(2) | left < right → backward | `你的 \| 幫忙` |
| 好(1) 的 沒問題(3) | left < right → backward | `好的 \| 沒問題` |

### Pass 5 — `absorbStraySingletons`

Leftover single-Han chunks merge into a multi-char neighbour. **Backward first** with a 3-CJK cap (tight rhythm); **forward fallback** at cap 4 so V + V-aspect compounds like `去 + 吃飯了 → 去吃飯了` can merge. Skip forward-glue into a single-Han next so we don't fuse two separately-recognised words ICU split apart.

## Two-platform parity

The Kotlin port at `android-spike/.../ChunkShaper.kt` is byte-equivalent — same set membership, same ordering, same caps. Both sides use the same `Tests/Fixtures/rsvp-gold-corpus.tsv` as the contract. When iOS's F1 moves, Android's should too (and vice versa).

`tokenizeCJKSegment` on both platforms got the same upstream fix for **leading punctuation preservation**: an opening 「 before the first word of a CJK segment is buffered and prepended to the first token, so quoted phrases keep their opening mark instead of dropping it. NLTokenizer / ICU `BreakIterator` both skip standalone punctuation; without buffering the leading marks vanish.

## What the rules still don't solve

The remaining ~15% of corpus F1 sits in three categories:

1. **Quotes that span script boundaries** (`他說「Hello, world」就走了`) — the gold wants the entire `「Hello, world」` block as one chunk, but the script splitter naturally cuts it into a CJK segment + a Latin segment + a CJK segment.
2. **Latin internal multi-word phrases** (`VS Code`, `Pro Max`) — split by whitespace inside the Latin segment, no signal to merge.
3. **Classical-Chinese structural ambiguity** (`學而時習之不亦說乎` — gold wants `學而 | 時習之 | 不亦 | 說乎`, the four-character verse rhythm — without NER or a literary-Chinese model the shaper can't tell the difference between this and a name run).

These are flagged for **Phase 2** if needed:

- **LLM rescue for suspicious regions** — send only the worst-10-pattern regions to a small LLM at import time, cache the resulting boundaries on the article. ~$0.001/article, no runtime latency.
- **On-device BiLSTM/CRF model** — 5–15 MB, trained on user's accumulated corrections, fully offline.

Neither is necessary yet. The current rule set is competitive with jieba on the cases that matter and beats it on cross-script content (HTTP/1.1, 25°C, etc. — jieba splits all of those).

## How to extend the rules

When you find a chunk that flashes badly:

1. Add a row to `Tests/Fixtures/rsvp-gold-corpus.tsv` (or fix the existing row).
2. Run `swift run FastReadTokenizerStats` — confirm the row shows up in worst-10.
3. Read its `actual` vs `gold` diff. Find the rule that produced the wrong result.
4. Adjust the rule (most likely in `ChunkShaper.swift`), or add a new pass if it's a category we don't handle yet.
5. Re-run the stats. F1 should not regress overall.
6. Port the rule change to `ChunkShaper.kt` (Android parity).
7. Run `swift test` (parity-corpus + unit tests reflect the new output) and ship.

The corpus header documents this loop. The `--epub` mode lets you sample real content periodically so we know the corpus stays representative.
