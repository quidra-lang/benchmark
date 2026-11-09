Input 98000 produces "98000: digits=5 sum=17 reversed=89". All five original decimal digits, including three zeros, are counted; the digit sum is 9+8+0+0+0 and reversal produces the integer 89 without leading zeros.

remaining starts at the input; %10 extracts each digit and ~/=10 consumes it. digits++, sum += digit and reversed = reversed * 10 + digit retain the count, sum and reversed integer. The print line supplies labels.

The original input, digit extraction/count, sum, reversal and output are all needed to account for zeros and the exact line. A reversal-only excerpt would not establish the original digit count.
