# Memorise — M6: K-pop Lyrics reader (Spotify + tap-to-translate + add to deck)

- **Date:** 2026-11-18
- **Source:** the owner's feature request and the Q&A on 2026-11-18 (decisions in §2).
- **Owner of this file:** the planner. The implementor (core + app services) and frontend (SwiftUI) agents run the segments in §5 in order and tick the tracker (§7).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 apply.
  - Pure logic (models, parsing, tokenising, matching, request building) lives in `MemoriseCore`, which imports only Foundation. Networking, Keychain, `ASWebAuthenticationSession`, CryptoKit and the Translation framework live in the App target, behind protocols.
  - Inject clocks and RNGs (PKCE verifier, `state`, cache timestamps).
  - Persisted `Codable` types get a tolerant hand-written `init(from:)`, and every property has a default.
  - Never change or reuse an `ItemKey`, entry `id` or deck id. User-deck rules (M4-8) apply to saved words.
  - Never hand-edit the `.xcodeproj`. Edit `project.yml` and run `xcodegen generate`.
  - Record every deviation in PLAN.md §17.
- **Commits:** one segment = one commit, with the message given in the segment. Stage **only** the files that segment touches.
- **Tests:** none in this plan. The tester agent owns tests. Each segment gives acceptance criteria and reference examples.

---

## 1. Goal

A new **Lyrics** tab. You connect Spotify once, pick a song, and it starts playing in Spotify in the background. Memorise shows the song's **Hangul lyrics**, split into tappable words and phrases.

- **Tapping a word** shows a bubble above it with the meaning, a 🔊 button and **＋ Add to deck**.
- **Swiping left** shows the **full English translation**, fetched from the web, never machine-translated.
- **A track without Korean lyrics** (an English song, an instrumental, a song with no lyrics found) shows **"Lyrics not available for this track"**.
- **A saved word** becomes a normal card in a custom deck (new or existing). The lyric line is kept as the card's example, and the song appears under "Heard in".

```
┌─ Lyrics ─────────────────────────────┐   ┌─ Spring Day · BTS ─────────── ● ○ ┐
│ ▶ Now playing                         │   │                ┌──────────────┐   │
│   Spring Day · BTS             [Open] │   │                │ 보고 싶다     │   │
├───────────────────────────────────────┤   │                │ "I miss you"  │   │
│ 🔍 Search songs                       │   │                │ In: K-media   │   │
│ [Recent] [Playlists] [Liked]          │   │                │ 🔊   ＋ Add    │   │
│  Supernova · aespa                    │   │                └──────▼───────┘   │
│  Magnetic · ILLIT                     │   │  ‾‾보고 싶다‾‾ 이렇게 말하니까       │
│  …                                    │   │  더 보고 싶다                       │
└───────────────────────────────────────┘   │  너희 사진을 보고 있어도             │
                                            └────────────── swipe ← English ────┘
```

## 2. Owner decisions (2026-11-18)

| ID | Question | Decision |
|---|---|---|
| L-D1 | Synced (karaoke) lyrics? | **No.** Static lyrics; the song plays in Spotify in the background. |
| L-D2 | Lyrics source | **Fetched from the web at runtime**, never bundled: Hangul from **LRCLIB**, with **Genius** as the Hangul fallback; English from Genius's **"English Translation"** pages. Owner accepts that Genius is page-scraped (brittle, terms grey) for personal use. |
| L-D3 | Spotify account | **Premium** (needed to start playback, and to own a Development Mode app). |
| L-D4 | iOS version | Owner's phone is on iOS 18+. **Deployment target is raised to iOS 18.0 for the whole app** (planner decision: single user, and it removes `@available` gating around the Translation framework). |
| L-D5 | Word meanings in the bubble | **Our decks first** (curated meaning), then **Apple's on-device Translation** (ko→en) for anything else. |
| L-D6 | No English translation found | Show **"English translation not available"**. No machine translation of whole lyrics. |
| L-D7 | "Not available" rule | Based on the **lyrics**, not on Spotify genre: no lyrics, instrumental, or Hangul share below the threshold (§4.3) → "Lyrics not available for this track". |
| L-D8 | Saved card content | Word + meaning + **the lyric line as the example** + a "Heard in" song reference. Kept on device only (same rule as M5 "My snippet"). |
| L-D9 | Saving words | **＋ Add to deck** opens a sheet: pick an existing custom deck or **+ New deck…**. |

**Copyright rule (extends M5 §2):** lyrics and translations are never bundled, never exported, and never sent anywhere except the request to the source site that fetches them. They are cached only in `Application Support/LyricsCache/`. A saved card's example line is the one exception the owner chose (L-D8), and it lives in the user's own deck file.

**No links rule (M5):** the reader footer shows source **names only** ("Lyrics: LRCLIB · Translation: Genius"), not tappable links.

**PLAN §1 deviation:** this is the first feature that uses the network and accounts. Record it in §17 (done in segment L0).

## 3. Verified external facts (checked 2026-11-18)

Spotify (February/March/May/July 2026 changelogs and the Feb 2026 migration guide):
- A Development Mode app allows **5 users**, and the **owner must have Premium**.
- These still work: `GET /me/player/currently-playing`, `GET /me/player/recently-played`, `PUT /me/player/play`, `GET /me/playlists`, `GET /me/tracks` (saved songs), `GET /tracks/{id}`, `GET /search`.
- **Playlist contents are `GET /playlists/{id}/items`** (`/tracks` is removed). In the response, `tracks` becomes `items` and each row's `track` becomes `item`. It returns items only for playlists **the user owns or collaborates on**; for others the `items` field is absent. The March revert did *not* undo this.
- `GET /search`: `limit` max **10**, default 5. Batch `GET /tracks?ids=` was removed. `popularity`, `available_markets`, `linked_from` were removed from tracks. `GET /me` has no `product` field, so we can't detect Premium.
- Redirect URIs must match exactly. HTTPS or loopback IPs are documented. Custom schemes aren't mentioned on that page, but Spotify's own iOS quick-start uses one, so we use `memorise-spotify://callback` and **check it in L0** (see L0 blocker rule).
- A 429 can carry `"reason": "QUOTA_EXCEEDED"`.

Other sources:
- LRCLIB: `GET https://lrclib.net/api/get?track_name=&artist_name=&album_name=&duration=` (seconds) returns `plainLyrics`, `syncedLyrics`, `instrumental`; a miss is 404. There's also `GET /api/search?track_name=&artist_name=`. No key. It asks clients to send a descriptive `User-Agent`.
- Genius: `GET https://api.genius.com/search?q=` with a free **client access token** returns song hits (`result.url`, `result.title`, `result.primary_artist.name`). Lyrics aren't in the API. They're on the song's HTML page inside `<div data-lyrics-container="true">` blocks, with `<br>` line breaks. English fan translations are separate songs whose primary artist is **"Genius English Translations"** and whose title looks like `"<Artist> - <Song> (English Translation)"`.

**Privacy:** requests carry no personal data. `User-Agent: Memorise/1.0 (personal, non-commercial)`. No email, no account name.

## 4. Design

### 4.1 Module split

| Layer | New code |
|---|---|
| `MemoriseCore/Lyrics/` (Foundation only) | `LyricsModels.swift`, `LyricsTokenizer.swift`, `PhraseMatcher.swift`, `KoreanLyricsCheck.swift`, `TrackQuery.swift`, `LRCLIBParser.swift`, `GeniusParser.swift`, `TranslationAlignment.swift`, `SpotifyModels.swift`, `SpotifyRequests.swift`, `LyricsCacheFile.swift`, `WordLookup.swift` |
| App `Services/Lyrics/` | `HTTPClient.swift` (protocol + `URLSession` impl), `SpotifyAuth.swift`, `KeychainStore.swift`, `SpotifyClient.swift`, `LyricsService.swift` (provider chain + cache), `LyricsCacheStore.swift` (actor), `GlossService.swift` (deck lookup + Translation) |
| App `Features/Lyrics/` (frontend) | `LyricsHomeView.swift`, `LyricsHomeViewModel.swift`, `LyricsReaderView.swift`, `LyricsReaderViewModel.swift`, `KoreanLyricsPage.swift`, `EnglishLyricsPage.swift`, `WordFlowLayout.swift`, `WordBubble.swift`, `AddToDeckSheet.swift` |

### 4.2 Core models (`LyricsModels.swift`)

```swift
public struct TrackInfo: Hashable, Codable, Sendable {      // from Spotify
    public var spotifyID: String        // "11dFghVXANMlKmJXsNCbNl"
    public var title: String            // as Spotify returned it
    public var titleKo: String?         // from the ko-KR request (§4.4), when different
    public var artists: [String]        // primary first
    public var album: String
    public var durationMs: Int
    public var releaseYear: Int?        // first 4 chars of album.release_date
    public var artworkURL: String?      // smallest image ≥ 64 px
}

public struct LyricLine: Hashable, Codable, Sendable {
    public var text: String             // one display line, trimmed
    public var isSectionHeader: Bool    // Genius "[Chorus]" etc.: shown dimmed, never tokenised
}

public struct LyricsDocument: Hashable, Codable, Sendable {
    public var korean: [LyricLine]
    public var english: [LyricLine]?    // nil = "English translation not available"
    public var koreanSource: String     // "LRCLIB" | "Genius"
    public var englishSource: String?   // "Genius"
}

public enum LyricsResult: Hashable, Sendable {
    case available(LyricsDocument)
    case notAvailable(Reason)           // UI shows one message for every reason
    public enum Reason: String, Sendable { case notFound, instrumental, notKorean }
}

public enum LyricToken: Hashable, Sendable {
    case word(text: String, range: Range<Int>)       // tappable eojeol, punctuation trimmed
    case phrase(text: String, entryID: String, tokenRange: ClosedRange<Int>) // deck multi-word match
    case plain(String)                                // Latin text, numbers, punctuation, "(", "~": not tappable
}
```

### 4.3 Korean check (`KoreanLyricsCheck`)

- `hangulShare(lines)` = Hangul syllables ÷ (Hangul syllables + Latin letters), ignoring section headers. Use the existing `Hangul.isSyllable`.
- **Korean** when `hangulShare ≥ 0.25` **and** there are at least **20** Hangul syllables. The constant is `LyricsConstants.minHangulShare = 0.25`, chosen because many K-pop songs are half English.
- Reference: an all-English song → 0.0 → not Korean. *Supernova*-style mixed lyrics (about 40 % Hangul) → Korean. A romanised-only page ("bogo sipda") → 0.0 → not Korean, so the chain tries the next provider.

### 4.4 Finding the lyrics (`LyricsService`, provider chain)

Input: `TrackInfo`. Output: `LyricsResult`. Check the cache first (§4.7).

1. **Names.** Spotify localises track/artist names by `Accept-Language`. When a track is opened, also fetch `GET /tracks/{id}` with `Accept-Language: ko-KR` and store any different name as `titleKo` (봄날 vs "Spring Day").
2. **Query normalising (`TrackQuery`, core):** strip `(feat. …)`, `(Feat. …)`, `[…]`, ` - Remix`/` - Live`/` - Inst.`/` - Japanese ver.` suffixes, and trailing whitespace. Keep the original for display.
   - Example: `"Seven (feat. Latto) - Clean Ver."` → `"Seven"`.
3. **Hangul lyrics, in order; stop at the first one that passes §4.3:**
   1. LRCLIB `/api/get` with title, first artist, album, duration (s). Try `titleKo` too when present.
   2. LRCLIB `/api/search` with title + first artist. Pick the best hit by duration (±3 s), title and artist (case-insensitive, normalised).
   3. Genius search `"<title> <artist>"` (and `titleKo`). Take the first hit whose artist matches and whose primary artist is not "Genius English Translations". Parse the page.
   - Use `plainLyrics`. When only `syncedLyrics` is present, strip the `[mm:ss.xx]` stamps.
   - `instrumental: true` → `.notAvailable(.instrumental)`. Nothing found → `.notFound`. Only non-Korean lyrics found → `.notKorean`.
4. **English translation** (only after Hangul succeeds): Genius search `"<artist> <title> English Translation"`. Accept a hit only if the primary artist is "Genius English Translations" and the normalised title contains both the artist and the song title (or `titleKo`). Parse the page. Not found or a parse failure → `english = nil` (L-D6). This is never an error.
5. **Networking rules:** 10 s timeout per request, at most 5 requests per song, no retries except one retry on a 5xx. Offline → the reader shows "You're offline. Lyrics you've opened before still work." with Retry.

### 4.5 Genius page parsing (`GeniusParser`, core, pure string processing)

- Collect the inner HTML of every `data-lyrics-container="true"` div, in order.
- Inside: `<br>` / `<br/>` → newline. Drop every other tag but keep its text. Decode HTML entities (`&amp; &#x27; &quot; &lt; &gt; &#NNN;`). Drop elements marked `data-exclude-from-selection="true"` (Genius header/contributor blocks).
- Lines matching `^\[.*\]$` become `isSectionHeader: true`. Collapse runs of blank lines to one; trim.
- **No match for the container** → return `nil`, log `Genius layout changed` in DEBUG. This is how we detect that Genius changed its HTML.

### 4.6 Tokenising and phrases (`LyricsTokenizer`, `PhraseMatcher`, `WordLookup`)

- Split each non-header line on whitespace. For each chunk: strip leading/trailing punctuation (`.,!?~…"'()[]「」`) into `.plain`; a remaining chunk with at least one Hangul syllable → `.word`; anything else → `.plain`. Example: `"보고 싶다, baby~"` → word 보고, word 싶다, plain ",", plain "baby~".
- **Phrases:** build a matcher from every catalog vocab entry (bundled and user decks) whose `hangul` contains a space. Normalise both sides: NFC, trailing `?!.~` dropped, final particle not stripped. Greedy, longest match first, left to right across consecutive word tokens. A match replaces its word tokens with one `.phrase`. Example: `보고 싶다` in ko_media → one tappable phrase.
- **Word lookup (`WordLookup.lookup(_ token:, in catalog)`):** return the first hit:
  1. exact `hangul` match
  2. the particle-stripped form (reuse `ScreenshotWords.stripParticle`, same ≥ 2-syllable rule)
  3. a trailing `?!.~`-normalised match

  It returns `(entry, deckTitle, matchedForm)`. Ownership order for ties = `headwordOwnershipOrder` (R7-F7), then user decks.
- **Known marker:** a word or phrase with a deck hit gets a subtle dotted underline. Everything else is plain.

### 4.7 Cache (`LyricsCacheFile`, `LyricsCacheStore`)

- One file per track: `Application Support/LyricsCache/<spotifyID>.json`.
- Contents: `{ schemaVersion: 1, track: TrackInfo, result: "available" | "notAvailable", reason?, document?, glosses: { "<token>": "<meaning>" }, fetchedAt }`. Decoding is tolerant; an unreadable file is deleted and refetched.
- `notAvailable` entries expire after **7 days** (lyrics may appear later). Available entries never expire. **Pull to refresh** in the reader forces a refetch.
- **Not in the data export** (copyright). Settings → Lyrics → **Clear lyrics cache**.

### 4.8 Bubble meanings (`GlossService`)

1. A deck hit (§4.6) → show the deck's `meaningText`, the matched dictionary form when it differs ("사랑해 → 사랑하다") and "In: <deck title>". No translation call.
2. Otherwise → the cached gloss, or the Translation framework.
   - A `TranslationSession` only exists inside a view's `.translationTask(_:action:)` closure and isn't `Sendable`. So `LyricsReaderView` attaches `.translationTask(configuration)` with `source: ko`, `target: en`. In that closure it batch-translates **all unique uncached word tokens of the song** with `session.translations(from:)`, then hands the results to `GlossService.store(_:for:)` (main actor), which writes them to the cache.
   - Tapping a word whose gloss isn't ready yet shows a spinner in the bubble. It fills in when the batch finishes.
   - Before the first use, check `LanguageAvailability().status(from: ko, to: en)`. `.supported` (not downloaded) → the system download prompt appears via `session.prepareTranslation()`. If it's declined or unsupported, the bubble says "Meaning unavailable. Download Korean in Settings → Apps → Translate", and **＋ Add** still works with an empty meaning field.
   - Label machine glosses "Auto-translated" in small caption text.

### 4.9 Spotify (`SpotifyAuth`, `SpotifyClient`, `SpotifyRequests`)

- **Auth:** Authorization Code with PKCE through `ASWebAuthenticationSession`, redirect `memorise-spotify://callback`, `prefersEphemeralWebBrowserSession = false`.
  - Scopes: `user-read-currently-playing user-read-playback-state user-modify-playback-state user-read-recently-played playlist-read-private playlist-read-collaborative user-library-read`.
  - The verifier is 64 random URL-safe chars (injected RNG). The challenge is base64url(SHA256) via CryptoKit in the app. `state` is checked on return.
  - `SpotifyRequests` (core) builds the authorize URL, token request bodies and API URLs, and decodes the JSON (`SpotifyModels`).
- **Tokens:** the access token is kept in memory and the refresh token in the Keychain (`KeychainStore`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Refresh 60 s before expiry and on any 401. A failed refresh → state `.disconnected`, and the UI shows Connect again.
- **Client ID:** from Info.plist key `SpotifyClientID`, filled from xcconfig (§5 L0). An empty value → the tab shows "Spotify isn't set up yet" with the setup steps from the README.
- **Picker sources:**
  - Now playing: `GET /me/player/currently-playing`, refreshed on appear, when the app becomes active, and with a manual refresh button. No polling timer.
  - Recent: `GET /me/player/recently-played?limit=50`, deduplicated by track id.
  - Playlists: `GET /me/playlists?limit=50` → `GET /playlists/{id}/items?limit=100`. Playlists the user doesn't own show "Spotify only shares songs from playlists you own", because `items` is absent.
  - Liked: `GET /me/tracks?limit=50`, with "Load more" by `offset`.
  - Search: `GET /search?type=track&limit=10&q=`, debounced 400 ms.
  - Skip non-track items (podcast episodes: `type != "track"`).
- **Playing:** tapping a song calls `PUT /me/player/play` with body `{"uris":["spotify:track:<id>"]}`, then opens the reader.
  - On 404 `NO_ACTIVE_DEVICE`, open `spotify:track:<id>` with `UIApplication.open`. The Spotify app starts it, and the reader is already open when the user comes back. Add `LSApplicationQueriesSchemes: [spotify]`.
  - On 403 (not Premium), show a one-line note; the reader still opens.
  - Opening a song from "Now playing" doesn't call play.
- **Errors:** 429 → wait for `Retry-After` and show "Spotify is busy, try again in N s"; `QUOTA_EXCEEDED` → "Spotify daily limit reached".

### 4.10 Saving a word (core change + `AddToDeckSheet`)

**Core fix needed first.** `UserDecks.EntryDraft` has no `sources`, and `UserDecks.replacing(...)` rebuilds `VocabEntry` **without `register`, `dialogue` and `sources`**. Rank reassignment would therefore silently drop a saved song reference.
- Add `public var sources: [MediaRef]` (default `[]`) to `EntryDraft`.
- `EntryDraft(_ e:)` copies `e.sources`.
- `entry(id:rank:)` passes `sources`.
- `replacing` passes `register`, `dialogue` and `sources` through unchanged.
- `UserDeckEditorView` keeps sources on edit (it doesn't show them).

**The sheet:**
- **Word:** prefilled with the deck's matched dictionary form if there was a hit, else the particle-stripped form (§4.6), else the tapped text. Editable.
- **Meanings:** prefilled with the bubble meaning, comma-separated, editable.
- **POS:** `UserDecks.guessedPartOfSpeech`, editable.
- **Example:** `ko` = the full lyric line (read-only preview). `en` = the aligned English line (§4.11), or empty.
- **Deck:** a picker of custom decks (`env.userDecks`), last used first (`AppSettings.lastLyricsDeckID`), plus **+ New deck…**. That's an inline title field, default title "My lyrics words", created with `UserDecks.newDeck` + `newDeckID`.
- **Heard in:** `MediaRef(kind: .song, title: <titleKo ?? title>, by: <artists joined ", ">, year: releaseYear, locator: "lyrics", context: "Saved while reading the lyrics.", citation: "spotify:track:<id>")`. Omit the source when `releaseYear` is missing or outside 1990…now (the validator rule).
- **Save:** `UserDecks.problems` must be empty → `UserDecks.adding` → `env.saveUserDeck`. If the hangul is already in the target deck → disable Save and show "Already in <deck>".
- **After saving:** toast "Added to <deck>", and the word's known marker appears.

The saved card then works like any user-deck card. `MediaSnippetView` already shows "Heard in" for entries with `sources`, and "My snippet" is available.

### 4.11 English page and alignment (`TranslationAlignment`)

- The English page shows the translation lines as fetched, with section headers styled as on the Korean page.
- **Alignment** (used only for the saved card's `en`): drop section headers and blank lines on both sides. If the line counts are equal, pair by index. Otherwise there's no alignment and `en = ""`. No guessing.

## 5. Segments

Order: L0 → L1 → L2 → L3 → L4 → L5 → L6 → L7 → L8 → L9. Frontend segments (L6–L8) may start with previews once L1's models exist.

### L0 — Setup, config and decision log (implementor)
**Files:** `project.yml`, new `App/Config/Base.xcconfig`, `App/Config/Secrets.example.xcconfig`, `.gitignore`, `README.md`, `PLAN.md` §4/§17.
1. `deploymentTarget` `iOS: "18.0"` (L-D4). Remove any `#available(iOS 18…)` checks that become always-true.
2. xcconfig: `Base.xcconfig` contains `#include? "Secrets.xcconfig"` and defaults `SPOTIFY_CLIENT_ID =` and `GENIUS_ACCESS_TOKEN =`. Attach it as the target's `configFiles` for Debug and Release. `Secrets.xcconfig` is gitignored; the example file has placeholders. CI builds with empty values. **`App/Config/Secrets.xcconfig` already exists on the owner's Mac with real values (2026-11-18). Never overwrite, print, `cat` or stage it, and never copy its values into any other file, log or commit.** The `.gitignore` rule is already committed (81be1dd).
3. Info.plist properties:
   - `SpotifyClientID: $(SPOTIFY_CLIENT_ID)`
   - `GeniusAccessToken: $(GENIUS_ACCESS_TOKEN)`
   - `CFBundleURLTypes` with scheme `memorise-spotify`
   - `LSApplicationQueriesSchemes: [spotify]`
4. README "Lyrics setup" for the owner:
   - Create a Spotify app at developer.spotify.com (Web API).
   - Add the redirect URI `memorise-spotify://callback`.
   - Add your account email under User Management.
   - Create a Genius API client at genius.com/api-clients. The form requires an **App Website URL** and a **Redirect URI**, but we never use Genius sign-in (only the client access token), so both are placeholders: website `https://github.com` (or your repo page) and redirect `https://example.com/callback`. Save, then press **Generate Access Token** on the client's page and copy that token. Don't use the Client ID or Client Secret.
   - Put both in `App/Config/Secrets.xcconfig`.
5. **Blocker rule:** if the Spotify dashboard rejects the custom-scheme redirect URI, stop and record it in §17. The planner will switch to a claimed HTTPS redirect.
6. PLAN.md: §4 "Min iOS 18.0", "Network: Lyrics tab only". §17 decision: the first network feature, iOS 18, no third-party deps (all Apple frameworks plus `URLSession`).

Commit: `M6-L0: iOS 18 target, lyrics config and secrets`
**Accept:** `xcodegen generate` and a build succeed with no `Secrets.xcconfig`. With a real file, `Bundle.main` returns both values. `git status` never shows `Secrets.xcconfig`.

### L1 — Core models, Korean check, tokenizer, phrase matcher, word lookup (implementor, core)
**Files:** `Lyrics/LyricsModels.swift`, `KoreanLyricsCheck.swift`, `LyricsTokenizer.swift`, `PhraseMatcher.swift`, `WordLookup.swift`, plus a `LyricsConstants` enum (`minHangulShare = 0.25`, `minHangulSyllables = 20`, `notAvailableTTLDays = 7`).
Implements §4.2, §4.3 and §4.6. `ScreenshotWords.stripParticle` becomes `public` if it isn't already.

Commit: `M6-L1: lyrics models, Korean check, tokenizer and word lookup`
**Accept (reference examples):**
- `"보고 싶다, baby~"` → `[word 보고, word 싶다, plain ",", plain "baby~"]`. With ko_media present, it becomes `[phrase 보고 싶다, plain ",", plain "baby~"]` (whichever ko_media spelling exists; the content agent can name the id).
- `"너를"` → a lookup hit on 너 via particle stripping. `"사랑"` → an exact hit in Core 1.
- `hangulShare` of 30 Hangul syllables + 70 Latin letters = 0.30 → Korean. 10 syllables only → not Korean (below 20).
- Section header lines produce no tokens.

### L2 — Core parsers and query building (implementor, core)
**Files:** `TrackQuery.swift`, `LRCLIBParser.swift`, `GeniusParser.swift`, `TranslationAlignment.swift`, `SpotifyModels.swift`, `SpotifyRequests.swift`, `LyricsCacheFile.swift`.
Implements §4.4 step 2, §4.5, §4.7 (the file model), §4.9 (URL and body building, decoding) and §4.11. The Spotify models decode the **2026 field names** (`items`/`item` for playlist rows) and tolerate missing optional fields.

Commit: `M6-L2: LRCLIB, Genius and Spotify parsing; lyrics cache model`
**Accept:**
- `TrackQuery.normalise("Seven (feat. Latto) - Clean Ver.") == "Seven"`. `"Love wins all"` is unchanged.
- LRCLIB synced `"[00:12.34] 보고 싶다"` → `"보고 싶다"`.
- Genius fixture `<div data-lyrics-container="true">[Chorus]<br/>보고 싶다<br><a href="x">이렇게</a> 말하니까</div>` → lines `[Chorus]` (header), `보고 싶다`, `이렇게 말하니까`. HTML with no container → `nil`.
- `&#x27;` → `'`.
- Alignment: 10 vs 10 lines → pairs. 10 vs 11 → no alignment.
- The authorize URL has `code_challenge_method=S256`, the exact redirect and the scope list from §4.9.

### L3 — App networking, Keychain, Spotify auth and client (implementor, app)
**Files:** `Services/Lyrics/HTTPClient.swift`, `KeychainStore.swift`, `SpotifyAuth.swift`, `SpotifyClient.swift`, `AppEnvironment.swift` (adds `spotify: SpotifyClient`, `lyrics: LyricsService`).
Implements §4.9. `SpotifyClient` is `@MainActor @Observable` with `state: .notConfigured | .disconnected | .connecting | .connected(displayName)`. Methods: `connect()`, `disconnect()` (deletes the Keychain item), `nowPlaying()`, `recent()`, `playlists()`, `playlistItems(id:)`, `liked(offset:)`, `search(_:)`, `track(id:language:)`, `play(trackID:) -> PlayOutcome (.playing | .openedSpotify | .notPremium | .failed)`.

Commit: `M6-L3: Spotify PKCE sign-in, token refresh and Web API client`
**Accept:** connect → the Spotify consent screen → back in the app, connected. Killing and relaunching keeps you connected. A revoked app (removed in Spotify account settings) → back to Connect after the next call. `play` with the Spotify app closed → it opens Spotify playing the track.

### L4 — Lyrics service and cache (implementor, app)
**Files:** `Services/Lyrics/LyricsService.swift`, `LyricsCacheStore.swift` (actor, atomic writes, like `PersonalSnippetStore`), `SettingsView.swift` (a "Lyrics" section with **Clear lyrics cache** and **Disconnect Spotify**; frontend can restyle it).
Implements §4.4 and §4.7. `func lyrics(for: TrackInfo, forceRefresh: Bool) async -> LyricsOutcome (.result(LyricsResult) | .offline | .failed(String))`.

Commit: `M6-L4: lyrics provider chain with on-device cache`
**Accept (owner-device checks, 2026-11 catalogue):**
- BTS 봄날 / Spring Day → available, Hangul, English present.
- A NewJeans or ILLIT title track → available.
- An English-language song (e.g. any Ed Sheeran single) → not available.
- An instrumental track → not available.
- Opening the same song again in airplane mode → it loads from the cache.

### L5 — Bubble meanings (implementor, app)
**Files:** `Services/Lyrics/GlossService.swift`.
Implements §4.8. API: `func meaning(for token: LyricToken, track: String) -> GlossState (.deck(entry, deckTitle, form) | .auto(String) | .pending | .unavailable)`, `func pendingTexts(track:) -> [String]`, `func store(_ results: [String: String], track:)`.

Commit: `M6-L5: deck-first word meanings with on-device translation`
**Accept:** 사랑 → the Core meaning with "In: Korean Core 1". An uncommon eojeol → an "Auto-translated" gloss within a few seconds of opening the song. Airplane mode with the Korean pack installed → glosses still work.

### L6 — Lyrics tab and song picker (frontend)
**Files:** `MemoriseApp.swift` (a new tab **Lyrics**, `music.note.list`, tag **3**, shown second; existing tags 0/1/2 are unchanged), `Features/Lyrics/LyricsHomeView.swift`, `LyricsHomeViewModel.swift`.
- **States:**
  - not configured → setup text
  - disconnected → a **Connect Spotify** card
  - connected → a Now playing card (artwork, title, artist, Open), a search field, then a segmented control Recent / Playlists / Liked with lists
- **Rows:** artwork (`AsyncImage` 44 pt), title, artists.
- **Tap:** `play` → push `LyricsReaderView` in the tab's `NavigationStack`.
- Empty, loading and error states for every list. A `#Preview` per view and accessibility identifiers (`lyrics.connect`, `lyrics.search`, `lyrics.row.<id>`, `lyrics.nowPlaying`).

Commit: `M6-L6: Lyrics tab with Spotify song picker`
**Accept:** every picker source lists songs. Tapping one plays it in Spotify and opens the reader. Your own playlists open; a followed playlist shows the "only playlists you own" note.

### L7 — Reader: Korean page, bubble, English page (frontend)
**Files:** `LyricsReaderView.swift`, `LyricsReaderViewModel.swift`, `KoreanLyricsPage.swift`, `EnglishLyricsPage.swift`, `WordFlowLayout.swift` (a custom `Layout` that wraps tokens and keeps line breaks), `WordBubble.swift`.
- **Layout:** `TabView(.page)` with two pages; swiping left goes Korean → English. A page indicator labelled "한국어" / "English". Header: title (`titleKo` under the title when present) and artists.
- **Korean page:** each line is a `WordFlowLayout` of token views.
  - `.word` and `.phrase` are buttons. A phrase gets a soft highlight; known items get a dotted underline.
  - Section headers are dimmed and small.
  - Tapping a token → `.popover` anchored to it, with `.presentationCompactAdaptation(.popover)` so it's a bubble above the word on iPhone.
- **Bubble:** the token text, the dictionary form (if different), the meaning or a spinner, "In: <deck>" or "Auto-translated", 🔊 (`env.speech.speak`), and **＋ Add to deck** (opens L8's sheet).
- **English page:** the lines, or **"English translation not available"** (L-D6).
- **States:**
  - loading (skeleton lines)
  - **"Lyrics not available for this track"** (L-D7), with a small "Try again" (forced refresh)
  - offline message
  - pull to refresh
- **Footer:** "Lyrics: <source> · Translation: <source>", names only.
- Attaches `.translationTask` per §4.8. Dynamic Type supported; landscape works.

Commit: `M6-L7: lyrics reader with tap-to-translate bubbles and English page`
**Accept:** tapping a word shows the bubble above it within 1 frame (deck hit) or with a spinner (auto). Swiping shows the English page. An English song shows the not-available message on the Korean page, and the English page is disabled (no swipe).

### L8 — Add to deck (implementor core fix + frontend sheet)
**Files:** core `Korean/UserDecks.swift` (the §4.10 `sources` fix), `UserDeckEditorView.swift` (keep sources), `Features/Lyrics/AddToDeckSheet.swift`, `Support/AppSettings.swift` (`lastLyricsDeckID`, tolerant default nil).
Implements §4.10.

Commit: `M6-L8: add lyric words to custom decks`
**Accept:**
- Saving 너를 from a 봄날 line into a new deck "My lyrics words" creates `user.<hex>` with entry `.0001`: hangul 너, the example `ko` = the full line, and a source "봄날 · BTS · 2017 · lyrics".
- Practising that deck shows the card, and the reveal shows "Heard in".
- Editing the entry in the deck editor and deleting another entry keep the source.
- Saving a duplicate is blocked.
- The full data export includes the deck (user decks are already exported) but **no** lyrics cache.

### L9 — Docs and tracker (implementor)
**Files:** `PLAN.md` §6.1 (new persisted file `LyricsCache/*.json`, not exported), §11 (a Lyrics tab subsection pointing here), §15 (M6 status), §17 tracker row; `README.md` QA checklist (connect, pick, not-available, bubble, swipe, add to deck, offline cache, clear cache, disconnect).

Commit: `M6-L9: lyrics docs and QA checklist`

## 6. Out of scope (v1)
Synced/karaoke lyrics, playback controls in Memorise (play/pause/skip), romanisation of lyrics, grammar breakdowns, Apple Music, lyrics for non-Spotify songs, sharing, machine translation of whole songs.

## 7. Tracker

| Segment | Agent | Status | Notes |
|---|---|---|---|
| L0 Setup, iOS 18, secrets | implementor | ☑ | owner: create Spotify + Genius credentials |
| L1 Core models, tokenizer, lookup | implementor | ☑ | |
| L2 Core parsers | implementor | ☑ | |
| L3 Spotify auth + client | implementor | ☑ | |
| L4 Lyrics service + cache | implementor | ☑ | |
| L5 Bubble meanings | implementor | ☐ | |
| L6 Lyrics tab + picker | frontend | ☐ | |
| L7 Reader + bubble + English | frontend | ☐ | |
| L8 Add to deck | implementor + frontend | ☐ | core fix first |
| L9 Docs | implementor | ☐ | |
