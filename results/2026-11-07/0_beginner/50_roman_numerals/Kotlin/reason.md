# Task B selection: 50_roman_numerals / Kotlin

Starting 1994, greedy encoding subtracts 1000,900,90,4, producing MCMXCIV and remaining values 994,94,4,0. Decoding traverses those generated symbols, subtracting C before M, X before C and I before V, for signed contributions 1000,-100,1000,-10,100,-1,5 = 1994. The decoder reads roman, not the original integer.

The integer is supplied by the question. Keep conversion tables, complete encoder/reverse-converter operations and their shared encoded storage; unrelated input cases and final presentation do not establish the conversion boundary.

Selected complete source lines in `main.kt`: 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
