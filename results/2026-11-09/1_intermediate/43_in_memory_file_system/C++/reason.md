# Task B selection — C++

## Answer requirements shared across languages

1. Trace one resolution from absolute/relative starting node through path components, including dot components and symbolic-link expansion.
2. Distinguish a missing original final component from a missing component during link expansion, including the absent/error payload and propagated result.
3. Show the creating command consuming the result: a creation location permits creation; identical missing-entry text without that location does not.

## Selected source locations

- `main.cpp`: 52, 58, 59, 60, 61, 62, 152, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 175, 177, 179, 415, 416, 417, 418, 419, 420

## Evidence and language semantics

Resolution field order identifies each aggregate return. A Missing result carries creationParent only for an original final component; link expansion propagates the other Missing result. A missing ordinary final name returns its containing directory and that name. A missing link target returns the same displayed missing-entry reason without that creation payload; the failure escapes before the remaining original path can be treated as creatable. Absolute targets start at root; relative targets start at the containing directory. The excerpt alone supplies traversal, the original/recursive flag transition, return payload, and touch acceptance/error branches. Standard splitting, map lookup, optional/null, and branch semantics require no library implementation.

## Minimization and alternatives

The creating-command branch alone cannot distinguish the two missing cases. The resolver alone does not establish whether its payload authorizes creation, so both are retained. Other commands, node size/content operations, allocation internals, and command parsing are irrelevant to this routine question. Constructors are retained only where needed to interpret omitted/default result fields; error-format mappings are retained where the same displayed message is indirect. Pure block delimiters, blank lines, expansion-limit checks, and unrelated successful-action work were omitted where the selected conditions and indentation preserve the required scope. A full resolver including loop-limit handling would cost more tokens without affecting the stipulated missing-path comparison; no proposed source change is made.

The excerpt contains 884 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
