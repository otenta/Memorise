# Memorise — M5: Korean phrases from K-pop & K-dramas

- **Date:** 2026-11-16
- **Owner of this file:** planner. Implementor agents execute **K1–K5** in order and tick the tracker (§6). PLAN.md §16 conventions and `CLAUDE.md` apply.
- **Placement:** M5 depends only on the existing vocab pipeline. It does **not** need F10 (the deck registry), so it can be scheduled before M2. It must start **after G1** (frozen persisted coding), because K4 extends the export format.

---

## 1. Goal

A new Korean deck of **common phrases heard in popular K-pop songs and K-dramas**. The prompt works like any vocab card. On **OK / reveal**, the answer screen adds a **"Heard in" snippet panel** showing where the phrase comes from and how it's used:

```
┌──────────────────────────────────────────┐
│  보고 싶어                     🔊         │   ← existing answer (hangul, RR, meaning)
│  bogo sipeo · "I miss you" · casual      │
├──────────────────────────────────────────┤
│  💬 In a scene                            │   ← original mini-dialogue (author-written)
│   A  왜 전화했어?        Why did you call? │
│   B  그냥… 보고 싶어.    Just… I miss you. │
├──────────────────────────────────────────┤
│  🎵 Heard in                              │   ← verified media reference(s)
│   <Song title> · <Artist> · <Year>       │
│   Chorus — the narrator sings it to…     │   ← 1–2 sentence description, ours
├──────────────────────────────────────────┤
│  📝 My snippet  (+ add)                   │   ← user's own note, on-device only
└──────────────────────────────────────────┘
```

## 2. Content rules (non-negotiable: copyright and accuracy)

Song lyrics and drama scripts are copyrighted works, so the bundled deck JSON may contain **only**:

| Allowed in bundled content | Not allowed in bundled content |
|---|---|
| The phrase itself (a short common expression, e.g. 보고 싶어) | Lyric lines or verses beyond the phrase itself |
| Meaning, romanization, register, notes | Script/subtitle transcripts of a scene |
| **Original** mini-dialogues written by the content author, in the style of the context | Audio or video clips, album art, drama stills, logos |
| Media reference: title, artist/network, year, locator ("chorus", "S1 E4"), an **original** 1–2 sentence description of the moment | Links of any kind in the UI (owner decision 2026-11-16: names only) |

**Accuracy rule:** every media reference must be **verified**: the phrase really occurs in that song or episode. Each reference records the `citation` used to verify it (an official lyrics page, the official MV, or the broadcaster's episode page). **Agents must never invent a reference.** If a reference can't be verified, drop it and keep the phrase with fewer or no references. A phrase with zero verified references is still a valid card; the panel then shows only the dialogue.

The **"My snippet"** feature (K4) is where you can keep your own lyric line or quote for personal study. It is stored only on your device, is never bundled, and is never sent anywhere.

## 3. Data model: vocab deck schema v2 (additive)

The phrases deck reuses `VocabDeck` / `VocabEntry`, so no new `CardContent` case is needed and the scheduler, stats, introduction gating and TTS work unchanged. Schema v2 adds **optional** fields only, so v1 files stay valid.

```json
{
  "schemaVersion": 2,
  "deckId": "ko.media",
  "title": "Korean · K-pop & K-drama",
  "subtitle": "Phrases you'll hear in songs and shows",
  "subject": "korean",
  "entries": [
    {
      "id": "ko.media.0001",
      "hangul": "보고 싶어",
      "romanization": "bogo sipeo",
      "meanings": ["I miss you"],
      "pos": "expression",
      "rank": 1,
      "tags": ["romance", "feelings"],
      "register": "casual",
      "notes": "Polite: 보고 싶어요. Past: 보고 싶었어 (I missed you).",
      "dialogue": [
        { "speaker": "A", "ko": "왜 전화했어?", "en": "Why did you call?" },
        { "speaker": "B", "ko": "그냥… 보고 싶어.", "en": "Just… I miss you." }
      ],
      "sources": [
        {
          "kind": "song",
          "title": "<verified title>",
          "titleKo": "<verified Korean title, optional>",
          "by": "<artist>",
          "year": 2017,
          "locator": "chorus",
          "context": "<original 1–2 sentence description of the moment>",
          "citation": "<URL used to verify, or \"owner\">"
        }
      ]
    }
  ]
}
```

**New fields**

| Field | Type | Rules |
|---|---|---|
| `register` | `"casual" \| "polite" \| "formal"` | Optional. Shown as a chip on reveal. K-drama phrases are mostly casual (반말), so this matters. |
| `dialogue` | `[DialogueLine]` (2–4 lines) | Optional. `speaker` ∈ {A, B, C}. Each `ko` ≤ 40 Hangul syllables, and `en` is non-empty. The entry's phrase **must appear** in at least one `ko` line. All lines are original writing. |
| `sources` | `[MediaRef]` (0–3) | Optional. |
| `MediaRef.kind` | `"song" \| "drama" \| "show" \| "film"` | Required. `show` covers variety and reality programmes (e.g. The Devil's Plan). |
| `MediaRef.title`, `by` | string | Required, non-blank. `by` = artist for songs, broadcaster/network for dramas. |
| `MediaRef.titleKo` | string | Optional. |
| `MediaRef.year` | int | Required, 1990…current year. |
| `MediaRef.locator` | string | Required. Songs: "intro", "verse 1", "chorus", "bridge", "outro". Screen: "S1 E4" or "E4". |
| `MediaRef.context` | string | Required, ≤ 200 chars. Original description; **must not quote more than the phrase itself**. |
| `MediaRef.citation` | string | Required in bundled files: an `https` URL, or the literal `"owner"` when the owner verified it from viewing. Never shown in the UI except in a DEBUG-only "Source check" disclosure. |

**No `url` field.** Owner decision (2026-11-16): the panel names the song or show only, with no links. The app stays fully offline. A stray `url` key in a file is ignored by the tolerant decoder and flagged by the validator.

**Headword rule change (v2 only):** for `pos == "expression"`, `hangul` may also contain `? ! , . …` (e.g. `진짜?`, `잠깐만!`). The v1 headword rule is unchanged for all other entries.

**ItemKeys:** `ko.media.NNNN#ko-en` / `#en-ko`, following the existing rule (never change or reuse).

## 4. Design decisions

- **Default direction is `ko→en`** for this deck. `en→ko` is allowed, but English glosses of phrases are ambiguous, so the en→ko prompt also shows the `register` chip and the first gloss only.
- **Which source is shown on reveal:** all sources are listed (max 3), first source expanded and the others collapsed. This is stable, not random, so reviews stay consistent.
- **No external links** (owner decision): references show names only, so the app stays fully offline and a session is never interrupted by leaving the app.
- **Reveal timing is unchanged:** the extra panel only adds content below the existing answer. Response time is still measured prompt → OK. The grade lockout (F4/G2) is unchanged. Long panels scroll; the Wrong/Correct controls stay pinned.
- **TTS:** the phrase speaks as today. Each dialogue line gets its own 🔊 (Korean voice, current speech rate).

---

## 5. Segments

### K1 — Schema v2 + validator (core)
**Files:** `Korean/Vocab.swift`, `Korean/DeckValidator.swift`, `Decks/DeckCatalog.swift`, PLAN.md §8.2.

1. `VocabDeckFile.currentSchemaVersion = 2`. Accept `1...2` (the validator errors only for versions outside that range).
2. Add `public struct DialogueLine: Hashable, Codable, Sendable { speaker, ko, en }` and `public struct MediaRef: Hashable, Codable, Sendable` with `Kind` enum and the fields from §3. Both get **tolerant** `init(from:)`, following the PLAN §16 convention. An unknown `kind` makes that **one ref** fail; it is dropped with a validator warning, and the entry is kept.
3. Add `register: Register?`, `dialogue: [DialogueLine]`, and `sources: [MediaRef]` to `VocabEntry` (`decodeIfPresent ?? []`; it already uses a hand-written decoder). Extend `init` with defaulted parameters so existing call sites compile unchanged.
4. Validator additions:
   - for files with `schemaVersion >= 2`, the `expression` headword punctuation rule applies
   - the dialogue rules (2–4 lines, length, phrase occurs in at least one line, using a whitespace/punctuation-insensitive contains)
   - the source rules from §3
   - `citation` is required: an `https` URL or the literal `"owner"`
   - a `url` key on a source is an error (the no-links rule). `MediaRef.init(from:)` records its presence in a non-encoded `hadURLKey` flag (add `url` to the decoding `CodingKeys` only), so the validator can see it.
5. Add `"ko_media"` to `DeckCatalog.bundledVocabFiles` (display order: after `ko_core_1`, before `ko_aion2`). Note that until K2 lands the file is missing, which shows the G3 "couldn't be loaded" row, so **K1 and K2 merge together**, or K1 lands with the list entry commented out.
6. PLAN.md §8.2: document v2 and link to this file.

**Accept:** both existing v1 files still validate with 0 errors; a hand-made 3-entry v2 sample validates; a sample with a non-allowlisted URL, a missing citation, or a dialogue missing the phrase produces exactly the expected errors. Use the DEBUG launch validation path, since D1 = No tests.

### K2 — Content: `ko_media.json` (about 80 entries)
**Files:** `Resources/Decks/ko_media.json`; a verification table in the PR description or commit message.
**Requires:** an agent with **web access** (to verify references), or the owner.

1. Pick **~80 phrases** (owner direction 2026-11-16: large, varied pool): the 40 candidates in §7 plus ~40 more, found while researching the priority artists and shows, across greetings, romance, friendship, conflict, encouragement, slang and address terms. Order them by `rank` = how common they are in everyday speech (most useful first).
2. For each phrase, write: meanings, RR romanization, register, notes (polite/casual counterparts), and **one original dialogue** (2–3 lines).
3. For each phrase, find **0–3 verified** media references, preferring well-known titles. For every reference:
   - open an official lyrics or episode source
   - confirm the phrase occurs there
   - record the URL as `citation`
   - write `context` in your own words
4. Aim for **≥ 70 % of entries having ≥ 1 verified source** and a mix of songs and dramas. Do not pad with unverified references to reach the target.
5. **Owner's priorities for references** (2026-11-16), in this order:
   - **K-pop:** BTS, LE SSERAFIM, TWICE, NewJeans, ILLIT, then other currently popular groups (newer 4th/5th-generation acts preferred over older catalogue).
   - **Variety / reality (`kind: "show"`) first, since its everyday speech is easiest:** Kian's Bizarre B&B (기안장), The Devil's Plan (데블스 플랜), then other popular reality/variety shows.
   - **Then popular K-dramas** (`kind: "drama"`). The owner has seen many and can name favourites during review.
   - Aim for a rough split of ≈ 50 % songs, 30 % shows, 20 % dramas among verified references. Never pad to hit it.
   - **Verifying shows:** there are no official transcripts, so a show reference may be verified by (a) an official clip or subtitle page, (b) reputable press quoting the line, or (c) **the owner** confirming they heard it (`citation: "owner"`, `verified-by: owner` in the table). Agents propose show references marked `PROPOSED` for the owner to confirm; they must not mark them verified themselves.
6. Tags come from a fixed set: `romance`, `feelings`, `friendship`, `family`, `conflict`, `encouragement`, `daily`, `exclamation`, `slang`, `address` (terms like 오빠/언니).
7. Deliver a **verification table**: phrase | reference | citation URL or "owner" | verified-by | date.

**Accept:**
- the validator shows 0 errors
- the owner spot-checks **10 random references**; any failure removes that reference, and two or more failures send K2 back for re-verification
- a `grep` of `context` and `dialogue` against the cited lyrics shows no copied lines beyond the phrase itself

### K3 — Reveal "snippet" panel (app)
**Files:** `App/Sources/Components/CardViews.swift` (`VocabAnswerView`), new `App/Sources/Components/MediaSnippetView.swift`.

1. `MediaSnippetView(entry:)` has three sections, each shown only when it has data:
   - **"In a scene"**: dialogue lines as chat bubbles (A on the left, B on the right, C on the left with a different tint). Each bubble shows Korean, with the English line below in secondary text and a 🔊 button.
   - **"Heard in"**: one row per source. SF Symbol `music.note` for songs, `tv` for drama/show, `film` for film. Shows title (plus `titleKo` if present), `by` · `year`, the locator chip, and the context text. Plain text only; no links or buttons.
   - **"My snippet"**: placeholder in K3; wired up in K4.
2. Embed it in `VocabAnswerView` below the existing content, only when `entry.dialogue` or `entry.sources` is non-empty, so the existing decks look unchanged.
3. Add the `register` chip ("casual" / "polite" / "formal") next to the romanization in both the prompt and answer views when present.
4. Accessibility: each bubble is a combined element ("Speaker A: …, meaning …"); each source row reads as "Heard in <title> by <by>, <year>, <locator>". Identifiers: `mediaSnippet`, `dialogueLine.<n>`, `mediaSource.<n>`.
5. `#Preview`s: an entry with dialogue + 2 sources; dialogue only; dark mode; largest Dynamic Type; landscape.

**Accept (device):**
- reveal on a media card shows the panel and the controls stay reachable
- core/aion2 cards are visually unchanged
- no tappable link appears anywhere in the panel

### K4 — "My snippet": personal, on-device notes
**Files:** new `App/Sources/Persistence/PersonalSnippetStore.swift`, `MediaSnippetView.swift`, `Persistence/Exporter.swift` (core) or the app export path, `Features/Settings/SettingsView.swift`.

1. Storage: a JSON file in Application Support (`personal_snippets.json`, a `[entryId: PersonalSnippet]` map), owned by an `actor PersonalSnippetStore`. **No SwiftData schema change.** `PersonalSnippet { text: String (≤ 500 chars), source: String? (free text, e.g. "song name"), updatedAt: Date }`, with tolerant decoding. Writes are atomic.
2. UI: in the reveal panel, "My snippet" shows the saved text, or a "+ Add your own snippet" button that opens a sheet with a multi-line text field, an optional source field, and Save/Delete. Opening the sheet during a session **pauses** the session (same path as the ✕ button) and resumes it on dismiss.
3. Export: add `personalSnippets` to the export JSON (optional key, so older importers ignore it). Bump `ExportSnapshot.schemaVersion` to 2. Reset-all asks separately: "Also delete my snippets?"
4. Privacy: snippets never leave the device except through the user's own Export share sheet.

**Accept:** add, edit and delete a snippet; it survives relaunch; it appears in the export; a session timer paused while editing shows no inflated response time.

### K5 — Integration and QA
1. Home: the new deck appears under Korean with the subtitle from the file.
2. Session Setup for the media deck: direction defaults to `ko→en`, and the topic filter shows the K2 tag set.
3. README manual QA checklist: add the K3/K4 device checks.
4. PLAN.md §17: tracker row for M5 and decision-log entries for every deviation.

---

## 6. Tracker

| Segment | Status | Notes |
|---|---|---|
| K1 Schema v2 + validator | ☐ | lands with K2, or with the list entry commented out |
| K2 Content `ko_media.json` | ☐ | needs web-capable agent or owner; verification table |
| K3 Reveal snippet panel | ☐ | |
| K4 My snippet (on-device) | ☐ | |
| K5 Integration & QA | ☐ | |

## 7. Candidate phrases for K2 (no media claims; references are found and verified in K2)

| Hangul | RR | Meaning | Register |
|---|---|---|---|
| 사랑해 | saranghae | I love you | casual |
| 보고 싶어 | bogo sipeo | I miss you | casual |
| 보고 싶었어 | bogo sipeosseo | I missed you | casual |
| 괜찮아 | gwaenchana | it's okay; I'm okay | casual |
| 화이팅 | hwaiting | you can do it!; go! | — |
| 대박 | daebak | awesome; no way | casual |
| 진짜? | jinjja | really? | casual |
| 어떡해 | eotteokae | what do I do?; oh no | casual |
| 미안해 | mianhae | I'm sorry | casual |
| 고마워 | gomawo | thanks | casual |
| 잘 자 | jal ja | good night | casual |
| 가지 마 | gaji ma | don't go | casual |
| 날 떠나지 마 | nal tteonaji ma | don't leave me | casual |
| 내 거야 | nae geoya | it's mine; you're mine | casual |
| 아이고 | aigo | oh my; oh dear | — |
| 헐 | heol | OMG; what?! | casual |
| 잠깐만 | jamkkanman | wait a moment | casual |
| 약속해 | yaksokae | I promise; promise me | casual |
| 믿어 줘 | mideo jwo | believe me; trust me | casual |
| 나만 믿어 | naman mideo | just trust me | casual |
| 걱정 마 | geokjeong ma | don't worry | casual |
| 그만해 | geumanhae | stop it | casual |
| 같이 가자 | gachi gaja | let's go together | casual |
| 정신 차려 | jeongsin charyeo | pull yourself together | casual |
| 밥 먹었어? | bap meogeosseo | have you eaten? | casual |
| 미쳤어? | michyeosseo | are you crazy? | casual |
| 너무 좋아 | neomu joa | I love it; it's so good | casual |
| 우리 헤어지자 | uri heeojija | let's break up | casual |
| 첫눈에 반했어 | cheonnune banhaesseo | I fell for you at first sight | casual |
| 사랑에 빠졌어 | sarange ppajyeosseo | I fell in love | casual |
| 왜 이래? | wae irae | why are you acting like this? | casual |
| 내 말 들어 | nae mal deureo | listen to me | casual |
| 어디 가? | eodi ga | where are you going? | casual |
| 행복해 | haengbokae | I'm happy | casual |
| 영원히 | yeongwonhi | forever | — |
| 꿈 같아 | kkum gata | it's like a dream | casual |
| 거짓말 | geojitmal | lie; liar! | — |
| 잘했어 | jalhaesseo | well done | casual |
| 수고했어 | sugohaesseo | good work; you've worked hard | casual |
| 오빠 | oppa | older brother (female speaker); affectionate term for an older man | address |

The K2 author checks the romanization of every entry against the official Revised Romanization rules before finalising. `-` marks register-neutral items.

## 8. Assumptions / open questions
- **DECIDED (owner, 2026-11-16):** a large pool, ~80 entries in the first release; more can be added in batches (ranks are append-only and ids are never reused).
- **DECIDED (owner, 2026-11-16):** no external links; references show the song or show name only.
- **DECIDED (owner, 2026-11-16):** content priorities as in K2 step 5 (BTS, LE SSERAFIM, TWICE, NewJeans, ILLIT and newer groups; reality shows such as Kian's Bizarre B&B and The Devil's Plan first, then popular dramas).
- **DECIDED (owner, 2026-11-16):** no audio clips in "My snippet", now or later. It stays text-only.
- **OPEN (owner, during K2 review):** favourite dramas to add, and confirmation of the `PROPOSED` show references.
