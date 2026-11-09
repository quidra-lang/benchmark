# Task B selection: 74_calendar_month / Java

August 2026 uses weekday 6 (Saturday) and 31 days. It emits August 2026 and Su Mo Tu We Th Fr Sa, then six blank width-two columns and 1 in the first week; the last week is 30 31. Seven-field weeks flush and clear, while the final partial week joins only present dates, giving no trailing blank columns. index>0 emits one blank separator before this month.

Retain month/name/offset data and every weekday/length/placement/flush/output stage. Imports and entry-point wrappers are unnecessary to derive the calendar.

Selected complete source lines in `Main.java`: 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
