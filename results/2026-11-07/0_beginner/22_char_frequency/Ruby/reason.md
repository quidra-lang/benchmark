Count uppercase and lowercase keys separately: the sentence contains P twice and lowercase p seven times, replacing their combined count nine. Remove lowercasing, filter both ASCII letter ranges, and emit occurring A..Z keys before a..z; spaces and ! still fail the letter filter.

The original sentence plus downcase.scan(/[a-z]/).tally shows where case is lost and nonletters are rejected. Retaining case with an A-Z/a-z filter lets sorted keys naturally put uppercase first.

Normalization, letter filtering, frequency keys and ordered output must be visible together: changing lowercasing alone would still exclude uppercase letters or print them in the wrong order.
