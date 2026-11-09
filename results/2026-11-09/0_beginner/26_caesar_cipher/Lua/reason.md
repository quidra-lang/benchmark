Shift letters by three within their own uppercase/lowercase alphabet, wrapping Z to C. The following comma remains unchanged. The constructed ciphertext is the value passed to decryption, which shifts back by the inverse amount.

gsub only invokes the callback for [A-Za-z]; byte/base/modulo/char maps each letter, leaving commas untouched. Strings are immutable and gsub constructs a new result, stored as ciphertext and supplied to caesar with -3.

Uppercase/lowercase branches, nonletter copying and encode-to-decode call data establish the wrapping and round trip. Alphabet-library internals are not needed to interpret those operations.
