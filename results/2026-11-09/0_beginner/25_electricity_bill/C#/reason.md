# Task B selection: 25_electricity_bill / C#

The tier expression charges min(u,120) at 30, the next capped 180 units at 36, and only u-300 excess at 40, plus one basic 900. Suzuki at 120 pays 4500; Tanaka at 300 pays 10980. total += bill adds each completed bill once, so no second basic charge is introduced.

Retain name/usage association, tier formula, bill accumulation and both individual/overall presentation sites. Main/import wrappers and culture setup are unrelated.

Selected complete source lines in `Program.cs`: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
