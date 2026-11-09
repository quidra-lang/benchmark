# Task B selection: 47_student_records / Java

Normalize the source name before creating its Student/tuple record: trim ASCII space at the two ends of name/names[i], without lowercasing. The construction line shows the actual field binding that all later sorting and output consume, so Tanaka is retained with its case and scores/total unchanged.

The actual name parameter/field and record creation suffice. The example name is supplied by the question, so full name data is unnecessary; consumers need not be expanded because normalizing before record construction supplies their normalized field.

Selected complete source lines in `Main.java`: 8, 14. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
