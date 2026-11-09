Shift letters by three within their own uppercase/lowercase alphabet, wrapping Z to C. The following comma remains unchanged. The constructed ciphertext is the value passed to decryption, which shifts back by the inverse amount.

String#tr maps A-Za-z to D-ZA-Cd-za-c, creates a new string without mutating message, and assigns encrypted. The inverse tr receives encrypted, not message.

Uppercase/lowercase branches, nonletter copying and encode-to-decode call data establish the wrapping and round trip. Alphabet-library internals are not needed to interpret those operations.
