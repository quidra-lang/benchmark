# Task B selection — 96_poker_hand_rank / Zig

## Common answer requirements

Classify and compare the two given hands, explain the ace-low special case, and follow the original hand strings to the output.

## Source evidence

The rank and suit tests classify both hands as ordinary straights. The ace-low ranks 2, 3, 4, 5 and 14 satisfy the special straight test and use the comparison sequence 5, 4, 3, 2, 1. The second hand uses 6, 5, 4, 3, 2 and wins at the first differing rank after the category ties. The selected input flow, score association and print expression show why the original input string is used even after the comparison order changes.

## Minimization

Selected complete lines of `main.zig`: L3, L5, L6, L7, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27, L28, L29, L30, L31, L32, L33, L34, L35, L36, L37, L38, L39, L40, L41, L42, L43, L44, L45, L46, L47, L48, L49, L50, L51, L52, L53, L54, L63, L64, L66, L67, L68, L69, L70, L71, L72, L73, L74, L85, L86, L87, L99, L100. The question supplies both literal hand strings. The selected processing shows how a supplied string is classified and remains associated with its comparison key. The lookup that formats the category label, unrelated hand literals and categories, and output setup do not supply any fact required about classification or preservation of the original hand.

The selected excerpt measures **1093 tokens** with `metric/tokenizer.py`.
