312047 seconds decomposes into 86 hours, 40 minutes and 47 seconds, producing "312047 seconds = 86:40:47". Hours use the full quotient by 3600 without modulo 24; minute/second remainders stay in 0..59. Zero padding and colons apply after decomposition.

The helper two converts int to text and pads with zero; ~/ and % compute components from the same s binding. The complete interpolation line identifies original seconds and separators.

The supplied total, quotient/remainder expressions and padded output are necessary to establish unbounded hours and bounded minute/second fields; no clock-date conversion is involved.
