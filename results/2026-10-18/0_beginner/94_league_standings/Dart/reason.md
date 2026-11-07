# Task B selection — 94_league_standings / Dart

## Common answer requirements

Derive both five-match records from the input and update rules, and identify the complete comparison and its first distinguishing key.

## Source evidence

The relevant score records give each team two wins, two draws and one loss, for eight points each. Tigers score and concede eight goals, while Wolves score and concede nine, so both goal differences are zero. The selected ranking orders by descending points, goal difference and goals scored, then by ascending name. Wolves therefore win the goals-scored tie-break before name is reached.

## Minimization

Selected complete lines of `main.dart`: L1, L2, L3, L4, L5, L6, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L20, L22, L25, L26, L27, L29, L30, L32, L34, L35, L37, L38, L39, L40, L41, L42, L43, L44, L45, L46, L47, L48, L49, L50, L51, L52, L53, L54, L55, L56, L57, L58, L59, L60, L61, L62, L63, L64, L65, L66, L67, L68, L69, L70, L71, L72, L73. The selected match literals and the binding that associates them with the update loop support the trace. An isolated closing delimiter on the input list adds no match data or scope distinction needed for this trace. Output formatting contributes no ranking rule.

The selected excerpt measures **750 tokens** with `metric/tokenizer.py`.

## Current token measurement

Task A: **1001 tokens**. Task B: **749 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
