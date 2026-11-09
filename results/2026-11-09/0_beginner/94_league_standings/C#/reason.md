# Task B selection: 94_league_standings / C#

C# OrderBy/ToArray and Kotlin sortedWith create a separate ordering container of stable team indices, leaving names and stats order intact; no change is needed. Java order.sort mutates its existing index-list order, so retain a copy before sorting or derive a sorted stream into a new list if that original index order is needed. Copying index ordering need not deep-copy team records.

The original name/stat containers and full sort construction establish ordering storage and key associations. Match accumulation and report printing do not change sort aliasing.

Selected complete source lines in `Program.cs`: 13, 14, 37, 38, 39. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
