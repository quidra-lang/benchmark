# Task B selection: 11_seconds_to_hms / C#

312047 decomposes into 86 hours, 40 minutes and 47 seconds. Integer quotient/remainder expressions apply no mod 24 to hours but mod 60 to minutes/seconds. D2 / %02d / padStart(2, zero) pads each component after decomposition, with colons between them, while the unchanged seconds binding supplies the left side: 312047 seconds = 86:40:47.

The loop input, quotient/remainder expressions and one formatting construction suffice. There is no custom conversion routine whose body must be added.

Selected complete source lines in `Program.cs`: 6, 7. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
