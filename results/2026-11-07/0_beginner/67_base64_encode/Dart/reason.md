Hello, World! encodes to "SGVsbG8sIFdvcmxkIQ==" and becomes "SGVsbG8sIFdvcmxkIQ" when padding is omitted; the quoted line is ""Hello, World!" -> "SGVsbG8sIFdvcmxkIQ"". Its last one-byte group keeps the zero-filled packing but drops two emitted = characters. Man has a complete group (TWFu), while empty input has no groups and stays empty.

codeUnitAt equals ASCII byte values for these strings. Ternaries zero-fill missing bytes, while two later write calls currently substitute =; conditionally omit those writes when no corresponding data symbol is needed. Keep the quote/arrow print expression.

ASCII-byte extraction, three-byte zero filling, six-bit index/alphabet lookup, padding branches and quoted output are needed for unpadded encoding. Decoder logic is unrelated to this output-only change.
