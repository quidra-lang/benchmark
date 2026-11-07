# Task B selection: 75_query_string_parse / C#

Decode key and value before testing duplicate membership, so added page=%32 resolves to the existing value 2 rather than a distinct spelling. Keep each key list in first-appearance order, appending only if the decoded value is absent, or use an insertion-ordered set. The second page group remains 2,3; sorted-key storage and quoted joining stay unchanged. Missing equals and empty values still decode to empty string and participate in the same rule.

The decoder/split, grouped accumulation and sorted-key output are the full affected dependency. Original query literals are unnecessary because the concrete appended item and existing values are supplied by the question.

Selected complete source lines in `Program.cs`: 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
