August 2026 begins on Saturday (offset 6) and has 31 days. The header is "August 2026" followed by "Su Mo Tu We Th Fr Sa"; the first week contains nineteen leading spaces followed by 1, and the last week is "30 31". Output wraps at seven weekday fields, stops after the final date without trailing blank columns and inserts one empty line between calendars.

Integer elapsed-day arithmetic and month accumulation give offset; last selects month length. Three-space blank columns, padLeft(2), weekday/final-day writeln and the alternate single-space write produce exact lines; k++ controls separators.

Month/year inputs, weekday/leap/month-length calculations, field/newline output and inter-calendar separation establish first and final weeks. Other month blocks cannot affect August layout.
