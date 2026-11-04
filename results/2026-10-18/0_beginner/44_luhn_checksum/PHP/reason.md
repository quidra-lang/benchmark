# Task B selection: 44_luhn_checksum / PHP

Show that the input and emitted membership identifier remain strings; trace right-based doubled positions and how the replacement check digit is calculated.

Only the individual characters are converted into arithmetic values. Counting with the rightmost digit at position one, double positions 2, 4, 6, 8, 10 and 12, subtracting 9 from doubled digits above 9. The weighted sum is 42. The original check digit 4 is not doubled. Removing it gives 38, whose modulo-10 complement is 2. The failed branch prints the original identifier, with its leading zero.

The literal and the arithmetic flow distinguish digit conversion from replacing the identifier with a number. The alternate valid-only output is not used for this input; its branch test is enough to establish why validation fails. Indexing from the right, reversing a copy, or comparing length minus the forward index all implement the same parity.

Source: `main.php`, original lines 3–4, 7–19, 21–23. The previous excerpt measures 389 tokens; this evidence set measures 370 tokens.
