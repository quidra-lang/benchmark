Shift letters by three within their own uppercase/lowercase alphabet, wrapping Z to C. The following comma remains unchanged. The constructed ciphertext is the value passed to decryption, which shifts back by the inverse amount.

The switch chooses alphabet base or -1; the ternary retains nonletters. String.fromCharCodes constructs a new immutable string from mapped code units; cipher is then passed to caesar with 23, the inverse shift modulo 26.

Uppercase/lowercase branches, nonletter copying and encode-to-decode call data establish the wrapping and round trip. Alphabet-library internals are not needed to interpret those operations.
