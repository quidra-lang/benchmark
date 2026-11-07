For 43981, the hexadecimal field becomes "hex=abcd". Change only the hexadecimal case conversion or format directive; zero stays "0", and no prefix or extra leading zeros are added. Decimal, binary and octal fields retain their existing expressions.

Remove the .upcase after n.to_s(16), whose documented digits are lowercase; the same line exposes the unaffected neighboring fields.

The complete numeral-output expression locates the hexadecimal case control; the selected base-conversion helper is included only where that call alone does not establish the emitted digits.
