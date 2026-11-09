# Task B selection: 59_date_add_days / C#

Replace forward day advancement with a decrement; on day zero move to the preceding month (wrapping January to December of the preceding year), then set day to that new month length with the same Gregorian February test. The 120-day case crosses 2023-11-01 to 2023-10-31 and ultimately 2023-07-18. Keep original separately and pass the evolving date to the existing zero-padded formatter; change the printed plus to minus.

Both month/leap rules, evolving/original date separation, formatter and affected day/output paths are required. Other case literals and unrelated setup do not add a boundary dependency.

Selected complete source lines in `Program.cs`: 5, 7, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
