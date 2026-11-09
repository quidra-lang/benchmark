The stored string "0128469655154" has checksum total 42, so it is invalid. Removing its rightmost check digit contribution 4 leaves 38; the replacement digit is 2. The complete line is "0128469655154: invalid (expected check digit 2)". The original string is never converted wholesale, preserving its initial zero.

codeUnitAt(i)-48 converts individual digits; (number.length-i)%2 identifies doubling parity from the right. The final code unit is subtracted before the modulo replacement calculation; interpolation preserves number.

The original digit string, alternating checksum contributions, check-digit exclusion and final expected-digit/output operations establish 42 and replacement 2. No whole-string numeric conversion is needed.
