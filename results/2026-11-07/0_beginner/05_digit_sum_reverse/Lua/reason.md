Input 98000 produces "98000: digits=5 sum=17 reversed=89". All five original decimal digits, including three zeros, are counted; the digit sum is 9+8+0+0+0 and reversal produces the integer 89 without leading zeros.

tostring and #digits preserve zeros for the count; gmatch("%d") and tonumber accumulate the sum; tonumber(digits:reverse()) produces 89 and string.format defines the entire line.

The original input, digit extraction/count, sum, reversal and output are all needed to account for zeros and the exact line. A reversal-only excerpt would not establish the original digit count.
