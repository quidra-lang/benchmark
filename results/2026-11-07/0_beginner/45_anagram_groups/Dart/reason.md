Apple sorts to the string signature "aelpp". No earlier word has that signature, so its absent key chooses a new group; an existing signature would reuse its prior group.

The preceding words establish the absent apple signature; groups is an empty String-to-list map. putIfAbsent calls () => [] only for an absent key, then add(word) updates that chosen list.

The actual Apple token, signature transformation and absent-key group insertion establish this first group. Group listing and unrelated later signatures are outside the dictionary-key question.
