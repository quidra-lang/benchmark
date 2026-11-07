312047 seconds decomposes into 86 hours, 40 minutes and 47 seconds, producing "312047 seconds = 86:40:47". Hours use the full quotient by 3600 without modulo 24; minute/second remainders stay in 0..59. Zero padding and colons apply after decomposition.

// gives whole hours; the 3600 and 60 remainders constrain the other components. The original seconds binding is also the first format argument.

The supplied total, quotient/remainder expressions and padded output are necessary to establish unbounded hours and bounded minute/second fields; no clock-date conversion is involved.
