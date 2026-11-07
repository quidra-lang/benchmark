The character reversal starts with "enil ": the four letters of the final word and its preceding space are separate elements. The word reversal starts with "line single": "line" is one element and reversed words are rejoined with single spaces.

string.reverse reverses ASCII bytes, which coincide with these characters; %S+ captures whole words and insertion at index 1 reverses word order. table.concat(words, " ") rejoins once per gap.

The two reversal expressions and their split/join operands distinguish character elements from word elements. Standard reversal and split semantics replace any library-source expansion.
