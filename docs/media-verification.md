# K-media phrase verification table (PLAN_M5 K2 / PLAN_R5_FIXES S7)

- **Entries:** 105 (`ko.media.0001`–`ko.media.0105`)
- **Entries with ≥ 1 verified reference:** 69 (66 %). **Target missed:** the target is ≥ 70 %. The 36 entries without a reference include the PLAN_M5 §7 candidates (e.g. 화이팅, 대박, 헐) that no checked song or press article contained. They stay as dialogue-only cards rather than getting stretched references; songs for these phrases can be added in a K2b pass.
- **Verified references:** 88 — songs 80 (91 %), shows 1 (1 %), dramas 7 (8 %). **Split target missed:** the target is ≈ 50 / 30 / 20. Songs could be checked line by line on lyrics pages, but dramas and shows have no public transcripts, so they rely on press that quotes the line. The split was not padded to hit the target.
- **Verified by:** a web-capable content agent, 2026-11-17. Every row was checked by reading the cited page.
- Song locators are `lyrics`: Bugs pages have no section markers, so sections were not verified (R6-5a).

**How songs were verified.** Lyrics come from the song's Bugs Music track page (`music.bugs.co.kr/track/<id>`), original Korean version. The phrase had to appear verbatim (ignoring spacing and punctuation). Bugs marks these lyrics as registered by Bugs, not as label-supplied. PLAN_R5_FIXES S7 lists Bugs as an accepted source, but the owner's spot-check may want a second source (Melon/Genie) for any doubtful row. Section labels (verse/chorus) are best estimates, because Bugs lyrics have no section markers.

**How dramas and shows were verified.** Each was checked against reputable Korean press that names the line (TenAsia, Vogue Korea, SPOTV News, XSports News, Hankyung, OSEN, Sports Khan, Kyunghyang). Where the article gives no episode, the locator is `series` (or `title` for a title phrase).

**Not used / DROPPED** (listed for the audit trail):
- 태양의 후예 "그 어려운 걸 제가 해냈습니다": the article (OSEN) gives a different wording, so this was not attached.
- 이상한 변호사 우영우 "기러기 토마토": no press source quoting it was found. The Woo greeting is a gesture, not a phrase.
- 사랑의 불시착 "한참 헤맸소": the article didn't quote it.
- 데블스 플랜: 데스룸 "산수할 줄 알아?": the article was paywalled and the line wasn't visible. **PROPOSED** for owner review; it is not in the JSON.
- 대환장 기안장 (Kian's Bizarre B&B): no press-reported catchphrase was found. There are no PROPOSED rows yet; the owner can add show references heard while watching (`citation: "owner"`).
- 무한도전 "그만큼 신나시는 거지": it isn't in the cited article.
- Phrases matched only as substrings (e.g. 설레 inside 설레이지, 함께 inside 함께니까) were not counted.

| id | hangul | kind | title | by | year | locator | citation | verified-by | status | date |
|---|---|---|---|---|---|---|---|---|---|---|
| ko.media.0001 | 사랑해 | song | FAKE LOVE | BTS | 2018 | lyrics | https://music.bugs.co.kr/track/31078328 | agent | VERIFIED | 2026-11-17 |
| ko.media.0003 | 미안해 | song | Life Goes On | BTS | 2020 | lyrics | https://music.bugs.co.kr/track/32075135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0003 | 미안해 | song | CHEER UP | TWICE | 2016 | lyrics | https://music.bugs.co.kr/track/30233414 | agent | VERIFIED | 2026-11-17 |
| ko.media.0004 | 괜찮아 | song | OMG | NewJeans | 2023 | lyrics | https://music.bugs.co.kr/track/6186207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0004 | 괜찮아 | song | FANCY | TWICE | 2019 | lyrics | https://music.bugs.co.kr/track/31559397 | agent | VERIFIED | 2026-11-17 |
| ko.media.0004 | 괜찮아 | song | FIRE (불타오르네) | BTS | 2016 | lyrics | https://music.bugs.co.kr/track/32563047 | agent | VERIFIED | 2026-11-17 |
| ko.media.0005 | 진짜? | song | Heart Shaker | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0005 | 진짜? | song | My World | ILLIT | 2024 | lyrics | https://music.bugs.co.kr/track/33133207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0006 | 보고 싶어 | song | Ditto | NewJeans | 2022 | lyrics | https://music.bugs.co.kr/track/6184997 | agent | VERIFIED | 2026-11-17 |
| ko.media.0006 | 보고 싶어 | song | Cookie | NewJeans | 2022 | lyrics | https://music.bugs.co.kr/track/6171084 | agent | VERIFIED | 2026-11-17 |
| ko.media.0006 | 보고 싶어 | song | What is Love? | TWICE | 2018 | lyrics | https://music.bugs.co.kr/track/31022636 | agent | VERIFIED | 2026-11-17 |
| ko.media.0007 | 보고 싶다 | song | Spring Day (봄날) | BTS | 2017 | lyrics | https://music.bugs.co.kr/track/30547148 | agent | VERIFIED | 2026-11-17 |
| ko.media.0008 | 몰라 | song | FAKE LOVE | BTS | 2018 | lyrics | https://music.bugs.co.kr/track/31078328 | agent | VERIFIED | 2026-11-17 |
| ko.media.0008 | 몰라 | song | YES or YES | TWICE | 2018 | lyrics | https://music.bugs.co.kr/track/31299324 | agent | VERIFIED | 2026-11-17 |
| ko.media.0008 | 몰라 | song | Cookie | NewJeans | 2022 | lyrics | https://music.bugs.co.kr/track/6171084 | agent | VERIFIED | 2026-11-17 |
| ko.media.0009 | 잠깐만 | song | LIKEY | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30826585 | agent | VERIFIED | 2026-11-17 |
| ko.media.0010 | 어떡해 | song | Heart Shaker | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0010 | 어떡해 | song | OMG | NewJeans | 2023 | lyrics | https://music.bugs.co.kr/track/6186207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0010 | 어떡해 | song | Tick-Tack | ILLIT | 2024 | lyrics | https://music.bugs.co.kr/track/33329629 | agent | VERIFIED | 2026-11-17 |
| ko.media.0011 | 너무해 | song | TT | TWICE | 2016 | lyrics | https://music.bugs.co.kr/track/30428038 | agent | VERIFIED | 2026-11-17 |
| ko.media.0011 | 너무해 | song | Dope (쩔어) | BTS | 2015 | lyrics | https://music.bugs.co.kr/track/4315827 | agent | VERIFIED | 2026-11-17 |
| ko.media.0012 | 그래 | song | FANCY | TWICE | 2019 | lyrics | https://music.bugs.co.kr/track/31559397 | agent | VERIFIED | 2026-11-17 |
| ko.media.0012 | 그래 | song | Spring Day (봄날) | BTS | 2017 | lyrics | https://music.bugs.co.kr/track/30547148 | agent | VERIFIED | 2026-11-17 |
| ko.media.0012 | 그래 | song | Talk that Talk | TWICE | 2022 | lyrics | https://music.bugs.co.kr/track/32629241 | agent | VERIFIED | 2026-11-17 |
| ko.media.0013 | 싫어 | song | YES or YES | TWICE | 2018 | lyrics | https://music.bugs.co.kr/track/31299324 | agent | VERIFIED | 2026-11-17 |
| ko.media.0013 | 싫어 | song | CHEER UP | TWICE | 2016 | lyrics | https://music.bugs.co.kr/track/30233414 | agent | VERIFIED | 2026-11-17 |
| ko.media.0013 | 싫어 | song | SET ME FREE | TWICE | 2023 | lyrics | https://music.bugs.co.kr/track/6192447 | agent | VERIFIED | 2026-11-17 |
| ko.media.0014 | 궁금해 | song | Boy With Luv (작은 것들을 위한 시) | BTS | 2019 | lyrics | https://music.bugs.co.kr/track/5863181 | agent | VERIFIED | 2026-11-17 |
| ko.media.0014 | 궁금해 | song | What is Love? | TWICE | 2018 | lyrics | https://music.bugs.co.kr/track/31022636 | agent | VERIFIED | 2026-11-17 |
| ko.media.0014 | 궁금해 | song | Cherish (My Love) | ILLIT | 2024 | lyrics | https://music.bugs.co.kr/track/33329626 | agent | VERIFIED | 2026-11-17 |
| ko.media.0015 | 좋아해 | song | Cherish (My Love) | ILLIT | 2024 | lyrics | https://music.bugs.co.kr/track/33329626 | agent | VERIFIED | 2026-11-17 |
| ko.media.0016 | 행복해 | song | IDOL | BTS | 2018 | lyrics | https://music.bugs.co.kr/track/31203512 | agent | VERIFIED | 2026-11-17 |
| ko.media.0017 | 기다릴게 | song | KNOCK KNOCK | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30557790 | agent | VERIFIED | 2026-11-17 |
| ko.media.0018 | 같이 가자 | song | UNFORGIVEN | LE SSERAFIM | 2023 | lyrics | https://music.bugs.co.kr/track/6197837 | agent | VERIFIED | 2026-11-17 |
| ko.media.0019 | 잊지 마 | song | ANTIFRAGILE | LE SSERAFIM | 2022 | lyrics | https://music.bugs.co.kr/track/6179181 | agent | VERIFIED | 2026-11-17 |
| ko.media.0020 | 그만해 | song | How Sweet | NewJeans | 2024 | lyrics | https://music.bugs.co.kr/track/6246205 | agent | VERIFIED | 2026-11-17 |
| ko.media.0021 | 꿈 같아 | song | FANCY | TWICE | 2019 | lyrics | https://music.bugs.co.kr/track/31559397 | agent | VERIFIED | 2026-11-17 |
| ko.media.0022 | 미쳤어? | song | Heart Shaker | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0023 | 뭐 어때 | song | Heart Shaker | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0024 | 너뿐이야 | song | OMG | NewJeans | 2023 | lyrics | https://music.bugs.co.kr/track/6186207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0025 | 예뻐 | song | LIKEY | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30826585 | agent | VERIFIED | 2026-11-17 |
| ko.media.0026 | 날 봐 | song | Like OOH-AHH (OOH-AHH하게) | TWICE | 2015 | lyrics | https://music.bugs.co.kr/track/30025213 | agent | VERIFIED | 2026-11-17 |
| ko.media.0027 | 꽉 잡아 | song | Boy In Luv (상남자) | BTS | 2014 | lyrics | https://music.bugs.co.kr/track/3387398 | agent | VERIFIED | 2026-11-17 |
| ko.media.0028 | 안녕 | song | Life Goes On | BTS | 2020 | lyrics | https://music.bugs.co.kr/track/32075135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0029 | 나야 | song | My World | ILLIT | 2024 | lyrics | https://music.bugs.co.kr/track/33133207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0030 | 걱정하지 마 | song | DNA | BTS | 2017 | lyrics | https://music.bugs.co.kr/track/30785785 | agent | VERIFIED | 2026-11-17 |
| ko.media.0031 | 말해줘 | song | Ditto | NewJeans | 2022 | lyrics | https://music.bugs.co.kr/track/6184997 | agent | VERIFIED | 2026-11-17 |
| ko.media.0032 | 말해봐 | song | Hype Boy | NewJeans | 2022 | lyrics | https://music.bugs.co.kr/track/6170217 | agent | VERIFIED | 2026-11-17 |
| ko.media.0032 | 말해봐 | song | Talk that Talk | TWICE | 2022 | lyrics | https://music.bugs.co.kr/track/32629241 | agent | VERIFIED | 2026-11-17 |
| ko.media.0033 | 망설이지 마 | song | Heart Shaker | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0034 | 어서 와 | song | Dope (쩔어) | BTS | 2015 | lyrics | https://music.bugs.co.kr/track/4315827 | agent | VERIFIED | 2026-11-17 |
| ko.media.0035 | 처음이지? | song | Dope (쩔어) | BTS | 2015 | lyrics | https://music.bugs.co.kr/track/4315827 | agent | VERIFIED | 2026-11-17 |
| ko.media.0036 | 관심 없어 | song | FEARLESS | LE SSERAFIM | 2022 | lyrics | https://music.bugs.co.kr/track/6160273 | agent | VERIFIED | 2026-11-17 |
| ko.media.0037 | 놀러 와 | song | Cookie | NewJeans | 2022 | lyrics | https://music.bugs.co.kr/track/6171084 | agent | VERIFIED | 2026-11-17 |
| ko.media.0038 | 이게 뭐지? | song | Magnetic | ILLIT | 2024 | lyrics | https://music.bugs.co.kr/track/33133208 | agent | VERIFIED | 2026-11-17 |
| ko.media.0039 | 니가 뭔데? | song | Boy In Luv (상남자) | BTS | 2014 | lyrics | https://music.bugs.co.kr/track/3387398 | agent | VERIFIED | 2026-11-17 |
| ko.media.0040 | 쉿 | song | CRAZY | LE SSERAFIM | 2024 | lyrics | https://music.bugs.co.kr/track/6259924 | agent | VERIFIED | 2026-11-17 |
| ko.media.0040 | 쉿 | song | Smart | LE SSERAFIM | 2024 | lyrics | https://music.bugs.co.kr/track/6234137 | agent | VERIFIED | 2026-11-17 |
| ko.media.0041 | 잘 가 | song | Like OOH-AHH (OOH-AHH하게) | TWICE | 2015 | lyrics | https://music.bugs.co.kr/track/30025213 | agent | VERIFIED | 2026-11-17 |
| ko.media.0042 | 바보야 | song | SIGNAL | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30653453 | agent | VERIFIED | 2026-11-17 |
| ko.media.0043 | 소리 질러 | song | Dance The Night Away | TWICE | 2018 | lyrics | https://music.bugs.co.kr/track/31139769 | agent | VERIFIED | 2026-11-17 |
| ko.media.0044 | 상관없어 | song | SET ME FREE | TWICE | 2023 | lyrics | https://music.bugs.co.kr/track/6192447 | agent | VERIFIED | 2026-11-17 |
| ko.media.0045 | 신경 안 써 | song | Smart | LE SSERAFIM | 2024 | lyrics | https://music.bugs.co.kr/track/6234137 | agent | VERIFIED | 2026-11-17 |
| ko.media.0046 | 내 말 믿어 | song | ETA | NewJeans | 2023 | lyrics | https://music.bugs.co.kr/track/6208880 | agent | VERIFIED | 2026-11-17 |
| ko.media.0047 | 내가 도와줄게 | song | ETA | NewJeans | 2023 | lyrics | https://music.bugs.co.kr/track/6208880 | agent | VERIFIED | 2026-11-17 |
| ko.media.0048 | 내 손 놓지 마 | song | OMG | NewJeans | 2023 | lyrics | https://music.bugs.co.kr/track/6186207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0049 | 눈을 감아 | song | Hype Boy | NewJeans | 2022 | lyrics | https://music.bugs.co.kr/track/6170217 | agent | VERIFIED | 2026-11-17 |
| ko.media.0050 | 필요 없어 | song | KNOCK KNOCK | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30557790 | agent | VERIFIED | 2026-11-17 |
| ko.media.0051 | 딱 한 번만 | song | I CAN'T STOP ME | TWICE | 2020 | lyrics | https://music.bugs.co.kr/track/32049967 | agent | VERIFIED | 2026-11-17 |
| ko.media.0052 | 숨지 마 | song | Life Goes On | BTS | 2020 | lyrics | https://music.bugs.co.kr/track/32075135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0053 | 외로워 마 | song | Mikrokosmos (소우주) | BTS | 2019 | lyrics | https://music.bugs.co.kr/track/31548669 | agent | VERIFIED | 2026-11-17 |
| ko.media.0054 | 만나러 갈게 | song | Spring Day (봄날) | BTS | 2017 | lyrics | https://music.bugs.co.kr/track/30547148 | agent | VERIFIED | 2026-11-17 |
| ko.media.0055 | 착각하지 마 | song | Boy In Luv (상남자) | BTS | 2014 | lyrics | https://music.bugs.co.kr/track/3387398 | agent | VERIFIED | 2026-11-17 |
| ko.media.0056 | 내버려 둬 | song | Go Go (고민보다 Go) | BTS | 2017 | lyrics | https://music.bugs.co.kr/track/30785791 | agent | VERIFIED | 2026-11-17 |
| ko.media.0057 | 가슴이 뛰어 | song | What is Love? | TWICE | 2018 | lyrics | https://music.bugs.co.kr/track/31022636 | agent | VERIFIED | 2026-11-17 |
| ko.media.0058 | 지금이야 | song | Heart Shaker | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0059 | 안아 줘 | song | SET ME FREE | TWICE | 2023 | lyrics | https://music.bugs.co.kr/track/6192447 | agent | VERIFIED | 2026-11-17 |
| ko.media.0060 | 조금만 더 | song | LIKEY | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30826585 | agent | VERIFIED | 2026-11-17 |
| ko.media.0061 | 연락할게 | song | CHEER UP | TWICE | 2016 | lyrics | https://music.bugs.co.kr/track/30233414 | agent | VERIFIED | 2026-11-17 |
| ko.media.0062 | 힘을 내 | song | CHEER UP | TWICE | 2016 | lyrics | https://music.bugs.co.kr/track/30233414 | agent | VERIFIED | 2026-11-17 |
| ko.media.0063 | 날이 좋아서 | drama | Guardian: The Lonely and Great God (도깨비) | tvN | 2016 | E6 | https://www.tenasia.co.kr/article/2016122630514 | agent | VERIFIED | 2026-11-17 |
| ko.media.0064 | 깐부 | drama | Squid Game (오징어 게임) | Netflix | 2021 | series | https://www.vogue.co.kr/2021/10/12/%ea%b9%90%eb%b6%80-%ed%95%a0%ec%95%84%eb%b2%84%ec%a7%80-%ec%98%a4%ec%98%81%ec%88%98-sns-%ec%8b%9c%ec%9e%91/ | agent | VERIFIED | 2026-11-17 |
| ko.media.0065 | 멋지다! | drama | The Glory (더 글로리) | Netflix | 2022 | series | https://v.daum.net/v/20230326192118444 | agent | VERIFIED | 2026-11-17 |
| ko.media.0066 | 이게 최선입니까? | drama | Secret Garden (시크릿 가든) | SBS | 2010 | series | https://www.xportsnews.com/article/1388887 | agent | VERIFIED | 2026-11-17 |
| ko.media.0067 | 폭싹 속았수다 | drama | When Life Gives You Tangerines (폭싹 속았수다) | Netflix | 2025 | title | https://www.hankyung.com/article/2025041152041 | agent | VERIFIED | 2026-11-17 |
| ko.media.0068 | 고백할까요? | drama | Descendants of the Sun (태양의 후예) | KBS2 | 2016 | E5 | https://www.osen.co.kr/article/G1110392450 | agent | VERIFIED | 2026-11-17 |
| ko.media.0069 | 오늘은 살아봐요 | drama | Lovely Runner (선재 업고 튀어) | tvN | 2024 | series | https://sports.khan.co.kr/article/202405281433003 | agent | VERIFIED | 2026-11-17 |
| ko.media.0070 | 무야호 | show | Infinite Challenge (무한도전) | MBC | 2010 | E195 | https://www.khan.co.kr/article/202103141850001 | agent | VERIFIED | 2026-11-17 |
| — | 산수할 줄 알아? | show | The Devil's Plan: Death Room (데블스 플랜: 데스룸) | Netflix | 2025 | series | https://www.elle.co.kr/article/1882018 | agent | PROPOSED | 2026-11-17 |
