August 2026 begins on Saturday (offset 6) and has 31 days. The header is "August 2026" followed by "Su Mo Tu We Th Fr Sa"; the first week contains nineteen leading spaces followed by 1, and the last week is "30 31". Output wraps at seven weekday fields, stops after the final date without trailing blank columns and inserts one empty line between calendars.

The adjusted year/month formula uses integer // and modulo; weekday counts leading two-space fields. The loop flushes at seven fields or final day and resets fields, with index>1 providing the calendar separator.

Month/year inputs, weekday/leap/month-length calculations, field/newline output and inter-calendar separation establish first and final weeks. Other month blocks cannot affect August layout.
