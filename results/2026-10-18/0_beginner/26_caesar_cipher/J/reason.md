# Task B selection: 26_caesar_cipher / J

Use a shift of thirteen on the original message and the inverse on the ciphertext. Thirteen is its own inverse modulo 26, so positive thirteen is also the inverse where an unsigned shift is used. Keep the existing separate alphabets and nonletter handling.

The named dyadic verb makes x the shift and y the input. The two alphabet halves and residue 26 wrap independently, absent letters are appended unchanged, and the accumulated result is returned. Change the left arguments to 13 and negative 13.

Complete main.ijs lines: 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 14, 17, 19. The shift arguments by themselves do not establish the custom operation’s wraparound or passthrough; the selected implementation and documented primitives do. The unchanged message literal and any print-only statements are unnecessary unless bundled with an edited call. The benchmark tokenizer counts 135 tokens in this excerpt.
