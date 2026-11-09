# Task B selection: 76_number_to_words / Java

UnderThousand(0) joins no parts and yields empty text, while only the whole-input zero branch adds zero. 71000 becomes seventy-one thousand with no zero suffix; 300019 becomes three hundred thousand nineteen, and 0 becomes zero. Only nonzero subparts enter the composition list; ordinary spaces join parts and the tens/ones condition supplies the hyphen in seventy-one.

Keep word tables and complete below-thousand/composition operations. The question supplies the three integers; input collection and final numeric-label output do not determine the word expressions.

Selected complete source lines in `Main.java`: 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
