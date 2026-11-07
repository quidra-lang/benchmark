For 43981, the hexadecimal field becomes "hex=abcd". Change only the hexadecimal case conversion or format directive; zero stays "0", and no prefix or extra leading zeros are added. Decimal, binary and octal fields retain their existing expressions.

Remove .toUpperCase() after n.toRadixString(16); toRadixString already uses lowercase digit letters and minimal magnitude digits.

The complete numeral-output expression locates the hexadecimal case control; the selected base-conversion helper is included only where that call alone does not establish the emitted digits.
