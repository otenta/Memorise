# K-media phrase verification table (PLAN_M5 K2 / PLAN_R5_FIXES S7)

- **Entries:** 105 (`ko.media.0001`–`ko.media.0105`)
- **R8-C1 (2026-11-17):** +121 K-pop chorus entries (`ko.media.0170`–`ko.media.0290`), 15 artists, every one with a `chorus` song reference. Rows are in the *R8-C1* section at the end of this file.
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

## Extension: ko.media.0106–0146 (41 entries, 2026-11-17)

- **Entries with ≥ 1 verified reference:** 9 of 41. **Verified references:** 11, all songs. The other 32 phrases stay as dialogue-only cards until a reference can be verified.
- Same method as above: each phrase had to appear verbatim in the Korean lyrics on the cited Bugs track page, ignoring only spaces and punctuation. Years come from the album page's 발매일 or the page's MV listing. 34 lyrics pages were read by a web-capable content agent.
- **Not used (substring only):** 사랑한다 inside 사랑한다는 (IU 밤편지, track 30598121), and 내가 지켜 줄게 only as 내가 지켜 줄게요 (로건 내가지켜줄게요, track 32356877). 너 때문이야 is in the title of Supreme Team's 너 때문이야 (track 2017955) but not in its lyrics.
- **Checked, no match:** TWICE What is Love?, 미쳤나봐, TT, SCIENTIST, 툭하면 톡, BDZ; BTS HOME, IDOL, N.O, Begin, ON, Blue & Grey; IU 좋은 날; NewJeans Ditto; LE SSERAFIM Perfect Night (English lyrics); ILLIT Lucky Girl Syndrome, Magnetic; G.NA 꺼져줄게 잘 살아 (only 꺼져줄게).

| id | hangul | kind | title | by | year | locator | citation | verified-by | status | date |
|---|---|---|---|---|---|---|---|---|---|---|
| ko.media.0106 | 괜찮을 거야 | song | 괜찮을거야 | Roy Kim | 2022 | lyrics | https://music.bugs.co.kr/track/6180024 | agent | VERIFIED | 2026-11-17 |
| ko.media.0107 | 다 잘될 거야 | song | 다 잘될 거야 | COOL | 2015 | lyrics | https://music.bugs.co.kr/track/4580183 | agent | VERIFIED | 2026-11-17 |
| ko.media.0107 | 다 잘될 거야 | song | 다 잘될 거야 | 김호연 | 2022 | lyrics | https://music.bugs.co.kr/track/32736715 | agent | VERIFIED | 2026-11-17 |
| ko.media.0112 | 기억나? | song | RE : WIND (이세계아이돌) | ISEGYE IDOL | 2021 | lyrics | https://music.bugs.co.kr/track/32416798 | agent | VERIFIED | 2026-11-17 |
| ko.media.0113 | 미치겠다 | song | Star Star Star (별별별 (☆★☆)) | Girls' Generation | 2010 | lyrics | https://music.bugs.co.kr/track/1920887 | agent | VERIFIED | 2026-11-17 |
| ko.media.0113 | 미치겠다 | song | Want U Back | 100% | 2013 | lyrics | https://music.bugs.co.kr/track/2986050 | agent | VERIFIED | 2026-11-17 |
| ko.media.0114 | 설렌다 | song | LIKEY | TWICE | 2017 | lyrics | https://music.bugs.co.kr/track/30826585 | agent | VERIFIED | 2026-11-17 |
| ko.media.0118 | 너 때문이야 | song | Insomnia | RIIZE | 2026 | lyrics | https://music.bugs.co.kr/track/6513728 | agent | VERIFIED | 2026-11-17 |
| ko.media.0124 | 끝났어 | song | 끝났어 | Lee Jung-hyun | 2000 | lyrics | https://music.bugs.co.kr/track/87780 | agent | VERIFIED | 2026-11-17 |
| ko.media.0127 | 같이 있어 줘 | song | 같이 있어줘 | 태하 & 화요비 | 2011 | lyrics | https://music.bugs.co.kr/track/2315707 | agent | VERIFIED | 2026-11-17 |
| ko.media.0128 | 시간이 없어 | song | RE : WIND (이세계아이돌) | ISEGYE IDOL | 2021 | lyrics | https://music.bugs.co.kr/track/32416798 | agent | VERIFIED | 2026-11-17 |
| ko.media.0140 | 사랑한다 | drama | I'm Sorry, I Love You (미안하다, 사랑한다) | KBS2 | 2004 | title | https://news.tf.co.kr/read/ogmeta/2216851.htm | agent | VERIFIED | 2026-11-17 |
| ko.media.0126 | 내 편 | drama | My Only One (하나뿐인 내편) | KBS2 | 2018 | title | https://m.seoul.co.kr/news/2018/09/15/20180915500043 | agent | VERIFIED | 2026-11-17 |

### Drama pass (2026-11-17)

- **Result:** 2 title references (사랑한다 → 미안하다, 사랑한다; 내 편 → 하나뿐인 내편), each confirmed against a press article that names the title, KBS2 and the airing year. No dialogue references were found, so 11 of 41 extension phrases now have a source (13 references: 11 songs, 2 dramas).
- **Read, no quoted line matched (dialogue only; headlines and journalist prose not counted):** Dailian 1413832 (엄마친구아들), 1048051 (갯마을 차차차), 1355809 (눈물의 여왕), 1244122 (어쩌다 마주친, 그대); Seoul Shinmun 밥 잘 사주는 예쁜 누나 (2018-04-19) and 욱씨남정기 (2016-04-18); Busan Ilbo 또 오해영 (2016-05-30); TenAsia 괜찮아 사랑이야 (2014082548144), 법대로 사랑하라 (2022092308944), 착하지 않은 여자들 (2015031672604); OSEN 드라마 명대사 7 (G1110407246), 넝쿨째 굴러온 당신 (G1109358506); GQ Korea 동백꽃 필 무렵 (2019-10-23); Maeil SKY 캐슬 (2018121309241100672); XSports News 2016 roundup (803658); Harper's Bazaar 66215, 67838, 74037 (partly behind a login wall).
- **Near misses not counted:** 심쿵한 / 심쿵할 (또 오해영, Busan Ilbo); 우리 결혼해요 (image caption only); 약속이나 지켜요, 가져다줄게요 (SKY 캐슬).
- **Why so few:** these extension phrases are everyday casual lines that press round-ups rarely quote; dialogue references will need the owner (`citation: "owner"`) or a phrase list chosen from known scenes.

## R8-C1 · K-pop chorus phrases (ko.media.0170–0290)

**How verified.** A script fetched each cited Bugs track page and counted the phrase in the lyrics (Hangul only, ignoring spacing and punctuation). A reference is listed only when the phrase occurs **at least twice**, so it sits in a repeated block (`locator: "chorus"`). The release year is taken from the track page. Phrases that occurred only once, or only inside a longer word, were dropped. Bundled text is the 1–6 word phrase only; dialogues are original.

**Not used:** songs whose repeated lines were English chants or onomatopoeia (e.g. Dynamite, Butter, Permission to Dance); Hangul fragments that are not usable on their own; phrases already in another `ko_*` deck (e.g. 보고 싶다, 사랑해).

| id | hangul | kind | title | by | year | locator | citation | verified-by | status | date |
|---|---|---|---|---|---|---|---|---|---|---|
| ko.media.0170 | 울고 싶지 않아 | song | 울고 싶지 않아 | SEVENTEEN | 2017 | chorus | https://music.bugs.co.kr/track/30661761 | agent | VERIFIED | 2026-11-17 |
| ko.media.0171 | 좀 더 힘을 내 | song | CHEER UP | TWICE | 2016 | chorus | https://music.bugs.co.kr/track/30233414 | agent | VERIFIED | 2026-11-17 |
| ko.media.0172 | 우연이 아니니까 | song | DNA | BTS | 2017 | chorus | https://music.bugs.co.kr/track/30785785 | agent | VERIFIED | 2026-11-17 |
| ko.media.0173 | 날 믿어봐 | song | Hype Boy | NewJeans | 2022 | chorus | https://music.bugs.co.kr/track/6170217 | agent | VERIFIED | 2026-11-17 |
| ko.media.0174 | 넌 그냥 믿으면 돼 | song | I AM | IVE | 2023 | chorus | https://music.bugs.co.kr/track/6195812 | agent | VERIFIED | 2026-11-17 |
| ko.media.0175 | 고민하지 마 | song | DRIP | BABYMONSTER | 2024 | chorus | https://music.bugs.co.kr/track/6268450 | agent | VERIFIED | 2026-11-17 |
| ko.media.0176 | 너와 난 운명이니까 | song | LOVEPOCALYPSE | ZEROBASEONE | 2026 | chorus | https://music.bugs.co.kr/track/6413595 | agent | VERIFIED | 2026-11-17 |
| ko.media.0177 | 질문은 계속돼 | song | Supernova | aespa | 2024 | chorus | https://music.bugs.co.kr/track/6245033 | agent | VERIFIED | 2026-11-17 |
| ko.media.0178 | 우린 하나가 돼 | song | Fly Up | RIIZE | 2025 | chorus | https://music.bugs.co.kr/track/6308575 | agent | VERIFIED | 2026-11-17 |
| ko.media.0179 | 이렇게 좋아해 본 적이 없어요 | song | 이렇게 좋아해 본 적이 없어요 | BOYNEXTDOOR | 2025 | chorus | https://music.bugs.co.kr/track/6293573 | agent | VERIFIED | 2026-11-17 |
| ko.media.0180 | 더는 못 참겠어 | song | OVERDRIVE | TWS | 2025 | chorus | https://music.bugs.co.kr/track/6360702 | agent | VERIFIED | 2026-11-17 |
| ko.media.0181 | 내 심장이 뛰네 | song | 이브, 프시케 그리고 푸른 수염의 아내 | LE SSERAFIM | 2023 | chorus | https://music.bugs.co.kr/track/6197839 | agent | VERIFIED | 2026-11-17 |
| ko.media.0182 | 날 말릴 순 없을걸 | song | Cherish (My Love) | ILLIT | 2024 | chorus | https://music.bugs.co.kr/track/33329626 | agent | VERIFIED | 2026-11-17 |
| ko.media.0183 | 누가 뭐라든지 넌 너야 | song | 쉿 (Shhh) | KISS OF LIFE | 2023 | chorus | https://music.bugs.co.kr/track/6205118 | agent | VERIFIED | 2026-11-17 |
| ko.media.0184 | 헤매도 돼 | song | IDESERVEIT | NMIXX | 2026 | chorus | https://music.bugs.co.kr/track/6463155 | agent | VERIFIED | 2026-11-17 |
| ko.media.0185 | 장난치지 마 | song | 울고 싶지 않아 | SEVENTEEN | 2017 | chorus | https://music.bugs.co.kr/track/30661761 | agent | VERIFIED | 2026-11-17 |
| ko.media.0186 | 준비하고 기다릴게 | song | KNOCK KNOCK | TWICE | 2017 | chorus | https://music.bugs.co.kr/track/30557790 | agent | VERIFIED | 2026-11-17 |
| ko.media.0187 | 우린 완전 달라 | song | DNA | BTS | 2017 | chorus | https://music.bugs.co.kr/track/30785785 | agent | VERIFIED | 2026-11-17 |
| ko.media.0188 | 아침은 너무 멀어 | song | Ditto | NewJeans | 2023 | chorus | https://music.bugs.co.kr/track/6184997 | agent | VERIFIED | 2026-11-17 |
| ko.media.0189 | 위험을 겁내지 마 | song | BLACKHOLE | IVE | 2026 | chorus | https://music.bugs.co.kr/track/6427499 | agent | VERIFIED | 2026-11-17 |
| ko.media.0190 | 용기를 좀 내봐 | song | I LIKE IT | BABYMONSTER | 2026 | chorus | https://music.bugs.co.kr/track/6461835 | agent | VERIFIED | 2026-11-17 |
| ko.media.0191 | 오직 너야 | song | LOVEPOCALYPSE | ZEROBASEONE | 2026 | chorus | https://music.bugs.co.kr/track/6413595 | agent | VERIFIED | 2026-11-17 |
| ko.media.0192 | 우린 어디서 왔나 | song | Supernova | aespa | 2024 | chorus | https://music.bugs.co.kr/track/6245033 | agent | VERIFIED | 2026-11-17 |
| ko.media.0193 | 느낀 대로 해 | song | Boom Boom Bass | RIIZE | 2024 | chorus | https://music.bugs.co.kr/track/6248695 | agent | VERIFIED | 2026-11-17 |
| ko.media.0194 | 꼭 안아 줄게요 | song | 이렇게 좋아해 본 적이 없어요 | BOYNEXTDOOR | 2025 | chorus | https://music.bugs.co.kr/track/6293573 | agent | VERIFIED | 2026-11-17 |
| ko.media.0195 | 하고 싶은 걸 따라가자 | song | 마음 따라 뛰는 건 멋지지 않아? | TWS | 2025 | chorus | https://music.bugs.co.kr/track/6300927 | agent | VERIFIED | 2026-11-17 |
| ko.media.0196 | 떨어져도 돼 | song | ANTIFRAGILE | LE SSERAFIM | 2022 | chorus | https://music.bugs.co.kr/track/6179181 | agent | VERIFIED | 2026-11-17 |
| ko.media.0197 | 고백은 너무 이른 걸 | song | jellyous | ILLIT | 2025 | chorus | https://music.bugs.co.kr/track/6316284 | agent | VERIFIED | 2026-11-17 |
| ko.media.0198 | 위험할수록 재밌잖아 | song | Midas Touch | KISS OF LIFE | 2024 | chorus | https://music.bugs.co.kr/track/6239848 | agent | VERIFIED | 2026-11-17 |
| ko.media.0199 | 손을 잡아 | song | KNOW ABOUT ME | NMIXX | 2025 | chorus | https://music.bugs.co.kr/track/6294415 | agent | VERIFIED | 2026-11-17 |
| ko.media.0200 | 널 찾아가야 돼 | song | 울고 싶지 않아 | SEVENTEEN | 2017 | chorus | https://music.bugs.co.kr/track/30661761 | agent | VERIFIED | 2026-11-17 |
| ko.media.0201 | 내일도 모레도 다시 와줘 | song | KNOCK KNOCK | TWICE | 2017 | chorus | https://music.bugs.co.kr/track/30557790 | agent | VERIFIED | 2026-11-17 |
| ko.media.0202 | 영원히 함께니까 | song | DNA | BTS | 2017 | chorus | https://music.bugs.co.kr/track/30785785 | agent | VERIFIED | 2026-11-17 |
| ko.media.0203 | 꿈에서 깨워주지 마 | song | Attention | NewJeans | 2022 | chorus | https://music.bugs.co.kr/track/6170060 | agent | VERIFIED | 2026-11-17 |
| ko.media.0204 | 꺾이지 않아 | song | REBEL HEART | IVE | 2025 | chorus | https://music.bugs.co.kr/track/6281197 | agent | VERIFIED | 2026-11-17 |
| ko.media.0205 | 너도 원하잖아 | song | I LIKE IT | BABYMONSTER | 2026 | chorus | https://music.bugs.co.kr/track/6461835 | agent | VERIFIED | 2026-11-17 |
| ko.media.0206 | 너 아니면 소용없어 | song | Doctor! Doctor! | ZEROBASEONE | 2025 | chorus | https://music.bugs.co.kr/track/33450022 | agent | VERIFIED | 2026-11-17 |
| ko.media.0207 | 왜 이제야 | song | Whiplash | aespa | 2024 | chorus | https://music.bugs.co.kr/track/6266734 | agent | VERIFIED | 2026-11-17 |
| ko.media.0208 | 시작해 봐 | song | Get A Guitar | RIIZE | 2023 | chorus | https://music.bugs.co.kr/track/6213292 | agent | VERIFIED | 2026-11-17 |
| ko.media.0209 | 그저 머물러줘요 | song | 이렇게 좋아해 본 적이 없어요 | BOYNEXTDOOR | 2025 | chorus | https://music.bugs.co.kr/track/6293573 | agent | VERIFIED | 2026-11-17 |
| ko.media.0210 | 함께라는 말이 좋아 | song | hey! hey! | TWS | 2024 | chorus | https://music.bugs.co.kr/track/6247698 | agent | VERIFIED | 2026-11-17 |
| ko.media.0211 | 그냥 포기해 | song | SPAGHETTI | LE SSERAFIM | 2025 | chorus | https://music.bugs.co.kr/track/6366519 | agent | VERIFIED | 2026-11-17 |
| ko.media.0212 | 날 좋아할까 | song | Tick-Tack | ILLIT | 2024 | chorus | https://music.bugs.co.kr/track/33329629 | agent | VERIFIED | 2026-11-17 |
| ko.media.0213 | 멈출 생각은 없지 | song | Get Loud | KISS OF LIFE | 2024 | chorus | https://music.bugs.co.kr/track/6264798 | agent | VERIFIED | 2026-11-17 |
| ko.media.0214 | 내일은 곧 오늘이 돼 | song | IDESERVEIT | NMIXX | 2026 | chorus | https://music.bugs.co.kr/track/6463155 | agent | VERIFIED | 2026-11-17 |
| ko.media.0215 | 네가 좋은 걸 어쩌나 | song | 어쩌나 | SEVENTEEN | 2018 | chorus | https://music.bugs.co.kr/track/31149474 | agent | VERIFIED | 2026-11-17 |
| ko.media.0216 | 더는 망설이지 마 | song | Heart Shaker | TWICE | 2017 | chorus | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0217 | 여기 내 손을 잡아 | song | Life Goes On | BTS | 2020 | chorus | https://music.bugs.co.kr/track/32075135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0218 | 알려주지 않아도 돼 | song | How Sweet | NewJeans | 2024 | chorus | https://music.bugs.co.kr/track/6246205 | agent | VERIFIED | 2026-11-17 |
| ko.media.0219 | 내가 정할게 | song | ATTITUDE | IVE | 2025 | chorus | https://music.bugs.co.kr/track/6284624 | agent | VERIFIED | 2026-11-17 |
| ko.media.0220 | 애써 외면하지 마 | song | Love In My Heart | BABYMONSTER | 2024 | chorus | https://music.bugs.co.kr/track/6268454 | agent | VERIFIED | 2026-11-17 |
| ko.media.0221 | 그녀를 놓치지 마 | song | GOOD SO BAD | ZEROBASEONE | 2024 | chorus | https://music.bugs.co.kr/track/33269244 | agent | VERIFIED | 2026-11-17 |
| ko.media.0222 | 문을 열어 | song | Next Level | aespa | 2021 | chorus | https://music.bugs.co.kr/track/32235760 | agent | VERIFIED | 2026-11-17 |
| ko.media.0223 | 다 모여봐 | song | Siren | RIIZE | 2024 | chorus | https://music.bugs.co.kr/track/6239850 | agent | VERIFIED | 2026-11-17 |
| ko.media.0224 | 내 손잡아 주세요 | song | 이렇게 좋아해 본 적이 없어요 | BOYNEXTDOOR | 2025 | chorus | https://music.bugs.co.kr/track/6293573 | agent | VERIFIED | 2026-11-17 |
| ko.media.0225 | 어디라도 좋을 것 같아 | song | BFF | TWS | 2024 | chorus | https://music.bugs.co.kr/track/6230616 | agent | VERIFIED | 2026-11-17 |
| ko.media.0226 | 이대로도 좋아 | song | Good Parts (when the quality is bad but I am) | LE SSERAFIM | 2022 | chorus | https://music.bugs.co.kr/track/6179184 | agent | VERIFIED | 2026-11-17 |
| ko.media.0227 | 상냥하게 다뤄줄게 | song | 체포하겠어 | ILLIT | 2026 | chorus | https://music.bugs.co.kr/track/6513869 | agent | VERIFIED | 2026-11-17 |
| ko.media.0228 | 너만 알고 있음 된 거야 | song | 쉿 (Shhh) | KISS OF LIFE | 2023 | chorus | https://music.bugs.co.kr/track/6205118 | agent | VERIFIED | 2026-11-17 |
| ko.media.0229 | 널 혼자 두지 않아 | song | Rock with you | SEVENTEEN | 2021 | chorus | https://music.bugs.co.kr/track/6132537 | agent | VERIFIED | 2026-11-17 |
| ko.media.0230 | 놓치기 싫어 | song | Heart Shaker | TWICE | 2017 | chorus | https://music.bugs.co.kr/track/30877135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0231 | 잠시 두 눈을 감아 | song | Life Goes On | BTS | 2020 | chorus | https://music.bugs.co.kr/track/32075135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0232 | 되돌아가긴 싫어 | song | Supernatural | NewJeans | 2024 | chorus | https://music.bugs.co.kr/track/6249329 | agent | VERIFIED | 2026-11-17 |
| ko.media.0233 | 행운은 늘 내 편인 걸 | song | ATTITUDE | IVE | 2025 | chorus | https://music.bugs.co.kr/track/6284624 | agent | VERIFIED | 2026-11-17 |
| ko.media.0234 | 더 이상 참고 싶지 않아 | song | Love In My Heart | BABYMONSTER | 2024 | chorus | https://music.bugs.co.kr/track/6268454 | agent | VERIFIED | 2026-11-17 |
| ko.media.0235 | 밤새 잠 못 드는 중이야 | song | Insomnia | ZEROBASEONE | 2024 | chorus | https://music.bugs.co.kr/track/33269247 | agent | VERIFIED | 2026-11-17 |
| ko.media.0236 | 겁내지 마 | song | Spicy | aespa | 2023 | chorus | https://music.bugs.co.kr/track/32845387 | agent | VERIFIED | 2026-11-17 |
| ko.media.0237 | 뭔가 달라 | song | Talk Saxy | RIIZE | 2024 | chorus | https://music.bugs.co.kr/track/6260454 | agent | VERIFIED | 2026-11-17 |
| ko.media.0238 | 다 똑같아 | song | 뭣 같아 | BOYNEXTDOOR | 2023 | chorus | https://music.bugs.co.kr/track/6214656 | agent | VERIFIED | 2026-11-17 |
| ko.media.0239 | 널 본 순간 알았어 | song | 널 따라가 (You, You) | TWS | 2026 | chorus | https://music.bugs.co.kr/track/6458715 | agent | VERIFIED | 2026-11-17 |
| ko.media.0240 | 실수해도 좋아 | song | Good Parts (when the quality is bad but I am) | LE SSERAFIM | 2022 | chorus | https://music.bugs.co.kr/track/6179184 | agent | VERIFIED | 2026-11-17 |
| ko.media.0241 | 두 손 두 발 들었지 | song | Cherish (My Love) | ILLIT | 2024 | chorus | https://music.bugs.co.kr/track/33329626 | agent | VERIFIED | 2026-11-17 |
| ko.media.0242 | 신경 쓰지 말자 | song | 청춘찬가 | SEVENTEEN | 2024 | chorus | https://music.bugs.co.kr/track/6243167 | agent | VERIFIED | 2026-11-17 |
| ko.media.0243 | 둘 중에 하나만 골라 | song | YES or YES | TWICE | 2018 | chorus | https://music.bugs.co.kr/track/31299324 | agent | VERIFIED | 2026-11-17 |
| ko.media.0244 | 끝이 보이지 않아 | song | Life Goes On | BTS | 2020 | chorus | https://music.bugs.co.kr/track/32075135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0245 | 이건 말로 설명 못해 | song | Bubble Gum | NewJeans | 2024 | chorus | https://music.bugs.co.kr/track/6243126 | agent | VERIFIED | 2026-11-17 |
| ko.media.0246 | 움츠리면 뭐할 건데 | song | ATTITUDE | IVE | 2025 | chorus | https://music.bugs.co.kr/track/6284624 | agent | VERIFIED | 2026-11-17 |
| ko.media.0247 | 멋대로 착각하지는 마 | song | FOREVER | BABYMONSTER | 2024 | chorus | https://music.bugs.co.kr/track/6250516 | agent | VERIFIED | 2026-11-17 |
| ko.media.0248 | 놓칠 수 없어 | song | SWEAT | ZEROBASEONE | 2024 | chorus | https://music.bugs.co.kr/track/33158531 | agent | VERIFIED | 2026-11-17 |
| ko.media.0249 | 용기 내 봐 | song | Spicy | aespa | 2023 | chorus | https://music.bugs.co.kr/track/32845387 | agent | VERIFIED | 2026-11-17 |
| ko.media.0250 | 내가 제일 좋아하는 거야 | song | Memories | RIIZE | 2023 | chorus | https://music.bugs.co.kr/track/6213293 | agent | VERIFIED | 2026-11-17 |
| ko.media.0251 | 아프지 않아 | song | 있잖아 | BOYNEXTDOOR | 2025 | chorus | https://music.bugs.co.kr/track/6363795 | agent | VERIFIED | 2026-11-17 |
| ko.media.0252 | 그거면 돼 | song | 내 이름을 불러줘 | TWS | 2026 | chorus | https://music.bugs.co.kr/track/6515241 | agent | VERIFIED | 2026-11-17 |
| ko.media.0253 | 나랑 저 너머 같이 가자 | song | UNFORGIVEN (feat. Nile Rodgers) | LE SSERAFIM | 2023 | chorus | https://music.bugs.co.kr/track/6197837 | agent | VERIFIED | 2026-11-17 |
| ko.media.0254 | 넌 이미 유죄 | song | 체포하겠어 | ILLIT | 2026 | chorus | https://music.bugs.co.kr/track/6513869 | agent | VERIFIED | 2026-11-17 |
| ko.media.0255 | 끝까지 가보자 | song | 손오공 | SEVENTEEN | 2023 | chorus | https://music.bugs.co.kr/track/6197215 | agent | VERIFIED | 2026-11-17 |
| ko.media.0256 | 하나만 선택해 | song | YES or YES | TWICE | 2018 | chorus | https://music.bugs.co.kr/track/31299324 | agent | VERIFIED | 2026-11-17 |
| ko.media.0257 | 저 미래로 달아나자 | song | Life Goes On | BTS | 2020 | chorus | https://music.bugs.co.kr/track/32075135 | agent | VERIFIED | 2026-11-17 |
| ko.media.0258 | 어디라도 따라갈래 | song | Bubble Gum | NewJeans | 2024 | chorus | https://music.bugs.co.kr/track/6243126 | agent | VERIFIED | 2026-11-17 |
| ko.media.0259 | 뭐든 될 대로 되라지 | song | Baddie | IVE | 2023 | chorus | https://music.bugs.co.kr/track/6218218 | agent | VERIFIED | 2026-11-17 |
| ko.media.0260 | 네 생각에 행복해 | song | Really Like You | BABYMONSTER | 2024 | chorus | https://music.bugs.co.kr/track/6268452 | agent | VERIFIED | 2026-11-17 |
| ko.media.0261 | 난 달려갈게 | song | In Bloom | ZEROBASEONE | 2023 | chorus | https://music.bugs.co.kr/track/32900421 | agent | VERIFIED | 2026-11-17 |
| ko.media.0262 | 삶의 주인공은 나 | song | Live My Life | aespa | 2024 | chorus | https://music.bugs.co.kr/track/6245041 | agent | VERIFIED | 2026-11-17 |
| ko.media.0263 | 난 놓치고 싶지 않아 | song | Memories | RIIZE | 2023 | chorus | https://music.bugs.co.kr/track/6213293 | agent | VERIFIED | 2026-11-17 |
| ko.media.0264 | 그냥 해 | song | ANIMAL | BOYNEXTDOOR | 2026 | chorus | https://music.bugs.co.kr/track/6509569 | agent | VERIFIED | 2026-11-17 |
| ko.media.0265 | 첫 만남은 너무 어려워 | song | 첫 만남은 계획대로 되지 않아 | TWS | 2024 | chorus | https://music.bugs.co.kr/track/6230613 | agent | VERIFIED | 2026-11-17 |
| ko.media.0266 | 계속 달릴 수 있어 | song | 손오공 | SEVENTEEN | 2023 | chorus | https://music.bugs.co.kr/track/6197215 | agent | VERIFIED | 2026-11-17 |
| ko.media.0267 | 너와 있을 때마다 이래 | song | Alcohol-Free | TWICE | 2021 | chorus | https://music.bugs.co.kr/track/32254320 | agent | VERIFIED | 2026-11-17 |
| ko.media.0268 | 넘어져도 다시 일어나 | song | ON | BTS | 2020 | chorus | https://music.bugs.co.kr/track/5863189 | agent | VERIFIED | 2026-11-17 |
| ko.media.0269 | 단 너뿐이야 | song | OMG | NewJeans | 2023 | chorus | https://music.bugs.co.kr/track/6186207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0270 | 어차피 못 찾을 테니 | song | Baddie | IVE | 2023 | chorus | https://music.bugs.co.kr/track/6218218 | agent | VERIFIED | 2026-11-17 |
| ko.media.0271 | 말하고 싶어 | song | Really Like You | BABYMONSTER | 2024 | chorus | https://music.bugs.co.kr/track/6268452 | agent | VERIFIED | 2026-11-17 |
| ko.media.0272 | 할 수 있을 것 같아 | song | ICONIK | ZEROBASEONE | 2025 | chorus | https://music.bugs.co.kr/track/6341493 | agent | VERIFIED | 2026-11-17 |
| ko.media.0273 | 뭘 어쩌겠어 | song | Home | SEVENTEEN | 2019 | chorus | https://music.bugs.co.kr/track/31425616 | agent | VERIFIED | 2026-11-17 |
| ko.media.0274 | 네가 있어 난 다시 웃어 | song | Feel Special | TWICE | 2019 | chorus | https://music.bugs.co.kr/track/31706264 | agent | VERIFIED | 2026-11-17 |
| ko.media.0275 | 아파도 돼 | song | 피 땀 눈물 (Blood Sweat & Tears) | BTS | 2016 | chorus | https://music.bugs.co.kr/track/30413061 | agent | VERIFIED | 2026-11-17 |
| ko.media.0276 | 난 행운아야 | song | OMG | NewJeans | 2023 | chorus | https://music.bugs.co.kr/track/6186207 | agent | VERIFIED | 2026-11-17 |
| ko.media.0277 | 멈추지 않아 | song | Off The Record | IVE | 2023 | chorus | https://music.bugs.co.kr/track/6217625 | agent | VERIFIED | 2026-11-17 |
| ko.media.0278 | 아마 모를걸 | song | Really Like You | BABYMONSTER | 2024 | chorus | https://music.bugs.co.kr/track/6268452 | agent | VERIFIED | 2026-11-17 |
| ko.media.0279 | 집 앞으로 갈게 | song | 붐붐 | SEVENTEEN | 2016 | chorus | https://music.bugs.co.kr/track/30473333 | agent | VERIFIED | 2026-11-17 |
| ko.media.0280 | 지금 너에게로 갈래 | song | FANCY | TWICE | 2019 | chorus | https://music.bugs.co.kr/track/31559397 | agent | VERIFIED | 2026-11-17 |
| ko.media.0281 | 넌 아름다워 | song | I NEED U | BTS | 2015 | chorus | https://music.bugs.co.kr/track/4315824 | agent | VERIFIED | 2026-11-17 |
| ko.media.0282 | 나 더는 묻지 않을래 | song | How Sweet | NewJeans | 2024 | chorus | https://music.bugs.co.kr/track/6246205 | agent | VERIFIED | 2026-11-17 |
| ko.media.0283 | 잘 봐 | song | ELEVEN | IVE | 2021 | chorus | https://music.bugs.co.kr/track/6138300 | agent | VERIFIED | 2026-11-17 |
| ko.media.0284 | 할 말 있어 | song | 붐붐 | SEVENTEEN | 2016 | chorus | https://music.bugs.co.kr/track/30473333 | agent | VERIFIED | 2026-11-17 |
| ko.media.0285 | 누가 먼저 좋아하면 어때 | song | FANCY | TWICE | 2019 | chorus | https://music.bugs.co.kr/track/31559397 | agent | VERIFIED | 2026-11-17 |
| ko.media.0286 | 함께하고 싶어 | song | 작은 것들을 위한 시 (Boy With Luv) | BTS | 2020 | chorus | https://music.bugs.co.kr/track/5863181 | agent | VERIFIED | 2026-11-17 |
| ko.media.0287 | 조용함이 더 좋아 | song | Hurt | NewJeans | 2022 | chorus | https://music.bugs.co.kr/track/6170218 | agent | VERIFIED | 2026-11-17 |
| ko.media.0288 | 내가 질투 나잖아 | song | 만세 | SEVENTEEN | 2024 | chorus | https://music.bugs.co.kr/track/6243177 | agent | VERIFIED | 2026-11-17 |
| ko.media.0289 | 미칠 것만 같아 | song | What is Love? | TWICE | 2018 | chorus | https://music.bugs.co.kr/track/31022636 | agent | VERIFIED | 2026-11-17 |
| ko.media.0290 | 어쩌다 보니 | song | 청춘찬가 | SEVENTEEN | 2024 | chorus | https://music.bugs.co.kr/track/6243167 | agent | VERIFIED | 2026-11-17 |
