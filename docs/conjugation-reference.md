# Conjugation reference (PLAN_M4 M4-6)

Reference forms for the tester. Every irregular class × every drilled form, plus the 마시다 / 되다 / 주다 / 오다 contractions and the special negatives. In a DEBUG build, `ConjugationDeck.selfCheck()` (run by `PersistedFormatCheck.run()`) checks the conjugator against exactly these rows. Keep both in sync.

These rows are standard textbook forms, written by hand. They were **not** checked against an online dictionary in this pass. Spot-check against a reference conjugator (for example the Wiktionary conjugation tables or the National Institute of Korean Language 표준국어대사전) and note any disagreement here.

"—" means no card is generated for that form. Adjectives never take -고 싶다. 없다 and 모르다 have no 안-negative and no "want to".

## Full rows

| Word | Class | present polite | past polite | future polite | present casual | present formal | negative polite | want to |
|---|---|---|---|---|---|---|---|---|
| 가다 | regular | 가요 | 갔어요 | 갈 거예요 | 가 | 갑니다 | 안 가요 | 가고 싶어요 |
| 먹다 | regular | 먹어요 | 먹었어요 | 먹을 거예요 | 먹어 | 먹습니다 | 안 먹어요 | 먹고 싶어요 |
| 오다 | regular | 와요 | 왔어요 | 올 거예요 | 와 | 옵니다 | 안 와요 | 오고 싶어요 |
| 마시다 | regular | 마셔요 | 마셨어요 | 마실 거예요 | 마셔 | 마십니다 | 안 마셔요 | 마시고 싶어요 |
| 되다 | regular | 돼요 | 됐어요 | 될 거예요 | 돼 | 됩니다 | 안 돼요 | 되고 싶어요 |
| 주다 | regular | 줘요 | 줬어요 | 줄 거예요 | 줘 | 줍니다 | 안 줘요 | 주고 싶어요 |
| 좋다 | regular (adj) | 좋아요 | 좋았어요 | 좋을 거예요 | 좋아 | 좋습니다 | 안 좋아요 | — |
| 하다 | ha | 해요 | 했어요 | 할 거예요 | 해 | 합니다 | 안 해요 | 하고 싶어요 |
| 공부하다 | ha | 공부해요 | 공부했어요 | 공부할 거예요 | 공부해 | 공부합니다 | 공부 안 해요 | 공부하고 싶어요 |
| 필요하다 | ha (adj) | 필요해요 | 필요했어요 | 필요할 거예요 | 필요해 | 필요합니다 | 안 필요해요 | — |
| 듣다 | d | 들어요 | 들었어요 | 들을 거예요 | 들어 | 듣습니다 | 안 들어요 | 듣고 싶어요 |
| 돕다 | b | 도와요 | 도왔어요 | 도울 거예요 | 도와 | 돕습니다 | 안 도와요 | 돕고 싶어요 |
| 춥다 | b (adj) | 추워요 | 추웠어요 | 추울 거예요 | 추워 | 춥습니다 | 안 추워요 | — |
| 낫다 | s | 나아요 | 나았어요 | 나을 거예요 | 나아 | 낫습니다 | 안 나아요 | 낫고 싶어요 |
| 모르다 | reu | 몰라요 | 몰랐어요 | 모를 거예요 | 몰라 | 모릅니다 | — | — |
| 부르다 | reu | 불러요 | 불렀어요 | 부를 거예요 | 불러 | 부릅니다 | 안 불러요 | 부르고 싶어요 |
| 쓰다 | eu | 써요 | 썼어요 | 쓸 거예요 | 써 | 씁니다 | 안 써요 | 쓰고 싶어요 |
| 바쁘다 | eu (adj) | 바빠요 | 바빴어요 | 바쁠 거예요 | 바빠 | 바쁩니다 | 안 바빠요 | — |
| 살다 | l | 살아요 | 살았어요 | 살 거예요 | 살아 | 삽니다 | 안 살아요 | 살고 싶어요 |
| 만들다 | l | 만들어요 | 만들었어요 | 만들 거예요 | 만들어 | 만듭니다 | 안 만들어요 | 만들고 싶어요 |
| 그렇다 | h (adj) | 그래요 | 그랬어요 | 그럴 거예요 | 그래 | 그렇습니다 | 안 그래요 | — |
| 이다 | copula | 이에요 | 이었어요 | 일 거예요 | 이야 | 입니다 | 아니에요 | — |

## Single forms (contractions and special cases)

| Word | Class | Form | Expected |
|---|---|---|---|
| 있다 | regular | negative polite | 없어요 |
| 맛있다 | regular | negative polite | 맛없어요 |
| 알다 | l | negative polite | 몰라요 |
| 없다 | regular | negative polite | — (no card) |
| 좋아하다 | ha | negative polite | 안 좋아해요 |
| 걷다 | d | present polite | 걸어요 |
| 닫다 | regular | present polite | 닫아요 |
| 어렵다 | b | present polite | 어려워요 |
| 새롭다 | b | present polite | 새로워요 |
| 짓다 | s | present polite | 지어요 |
| 빠르다 | reu | present polite | 빨라요 |
| 다르다 | reu | present polite | 달라요 |
| 크다 | eu | present polite | 커요 |
| 예쁘다 | eu | present polite | 예뻐요 |
| 아프다 | eu | present polite | 아파요 |
| 길다 | l | present formal | 깁니다 |
| 열다 | l | present formal | 엽니다 |
| 빨갛다 | h | present polite | 빨개요 |
| 하얗다 | h | present polite | 하얘요 |
| 보내다 | regular | past polite | 보냈어요 |
| 서다 | regular | present polite | 서요 |
| 배우다 | regular | present polite | 배워요 |
| 기다리다 | regular | past polite | 기다렸어요 |
| 있다 | regular | present formal | 있습니다 |


## Notes on the rules

- **Harmony:** a stem whose last vowel is ㅏ, ㅑ or ㅗ takes 아; any other vowel takes 어. Open ㅡ stems (바쁘, 모르) take their harmony from the syllable before.
- **Contractions:** 가+아 → 가, 오+아 → 와, 주+어 → 줘, 마시+어 → 마셔, 되+어 → 돼, 서+어 → 서, 보내+어 → 보내.
- **ㅂ-irregular:** ㅂ → 워 in general (추워요, 어려워요, 새로워요). Only the one-syllable ㅗ stems 돕다/곱다 take 와.
- **ㄹ stems:** ㄹ drops before ㅂ/ㄴ/ㅅ (삽니다), and they never add 으 (살 거예요).
- **Noun + 하다 negatives:** 안 goes before 하다 (공부 안 해요). 좋아하다/싫어하다 and -하다 adjectives keep 안 in front (안 좋아해요, 안 필요해요).
- **Lexical negatives:** 있다 → 없어요 (맛있다 → 맛없어요), 알다 → 몰라요, 이다 → 아니에요.
