Count uppercase and lowercase keys separately: the sentence contains P twice and lowercase p seven times, replacing their combined count nine. Remove lowercasing, filter both ASCII letter ranges, and emit occurring A..Z keys before a..z; spaces and ! still fail the letter filter.

string.lower currently loses case before gmatch. Keep the original string, broaden the pattern, and expand the output code traversal from 97..122 to two letter ranges in the required order.

Normalization, letter filtering, frequency keys and ordered output must be visible together: changing lowercasing alone would still exclude uppercase letters or print them in the wrong order.
