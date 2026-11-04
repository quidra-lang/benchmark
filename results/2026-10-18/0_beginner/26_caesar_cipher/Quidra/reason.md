# Task B selection: 26_caesar_cipher / Quidra

Use a shift of thirteen on the original message and the inverse on the ciphertext. Thirteen is its own inverse modulo 26, so positive thirteen is also the inverse where an unsigned shift is used. Keep the existing separate alphabets and nonletter handling.

The text import binds the translate extension. Normalize the signed shift modulo 26, then rotate each literal alphabet by the offset and translate by matched position. The documented API leaves unmatched code points unchanged; change the calls to 13 and negative 13.

Complete main.qui lines: 1, 3, 4, 5, 6, 7, 8, 11, 12. The shift arguments by themselves do not establish the custom operation’s wraparound or passthrough; the selected implementation and documented primitives do. The unchanged message literal and any print-only statements are unnecessary unless bundled with an edited call. The benchmark tokenizer counts 146 tokens in this excerpt.

Measurement: Task A 174; Task B 146. Tokenizer: metric/tokenizer.py, unchanged.
