For 43981, the hexadecimal field becomes "hex=abcd". Change only the hexadecimal case conversion or format directive; zero stays "0", and no prefix or extra leading zeros are added. Decimal, binary and octal fields retain their existing expressions.

Change %X to %x. The documented integer-format semantics establish lowercase digits and the absence of alternate-form prefixes or padding; binary(n) is unaffected and its implementation is unnecessary.

The complete numeral-output expression locates the hexadecimal case control; the selected base-conversion helper is included only where that call alone does not establish the emitted digits.
