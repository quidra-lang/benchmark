# Task B selection: 94_league_standings / Quidra

The question requires Tigers' and Wolves' five-match records, the first separating criterion, all preceding ties, and the full ordering. The nine selected match rows are exactly those involving at least one of these teams. Initialization, home/away lookup, parsing, both record calls and the complete record method show every update. The name array preserves its mapping to the Team array and the alphabetical final key.

Tigers and Wolves both finish with 2 wins, 2 draws, 1 loss, 8 points, and goal difference 0. Tigers have scored/conceded 8/8; Wolves 9/9. Points and goal difference therefore tie; descending goals-for puts Wolves before Tigers. The three key comprehensions show that points = 3*wins+draws, difference = scored-conceded and goals = scored. The sorted call records the complete priority order: points descending, difference descending, goals descending, names ascending. A name tie-break is reached only after all three numeric keys tie.

The documented value and mutation-authority rules plus .record's explicit body establish the per-team updates; no behavior is inferred only from its name. Collections index and native aligned-key sorting contracts need no library implementation. One match per line allows the six unrelated match records to be omitted. Keeping those records, or using the original packed rows, is a larger sufficient alternative. Printing and display sign formatting do not determine this comparison and are unchanged.

Selected complete main.qui lines: 1, 3, 4, 5, 6, 7, 8, 10, 11, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26, 27, 29, 32, 33, 34, 36, 37, 39, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py: Task A **883** tokens; Task B **637** tokens. These are source-token measures. This is a minimized sufficient selection among the reviewed alternatives, not a proof of a global minimum. Native compiler/output checks are recorded separately in validation.json.
