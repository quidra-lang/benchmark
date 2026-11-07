Hello, World! encodes to "SGVsbG8sIFdvcmxkIQ==" and becomes "SGVsbG8sIFdvcmxkIQ" when padding is omitted; the quoted line is ""Hello, World!" -> "SGVsbG8sIFdvcmxkIQ"". Its last one-byte group keeps the zero-filled packing but drops two emitted = characters. Man has a complete group (TWFu), while empty input has no groups and stays empty.

source:byte supplies ASCII bytes, the three-step pack zero-fills missing bytes and divisor-based indices select six-bit symbols. Replace emission of the i>remaining+1 padding branch with no append; the named encoded return value reaches the quoted formatter.

ASCII-byte extraction, three-byte zero filling, six-bit index/alphabet lookup, padding branches and quoted output are needed for unpadded encoding. Decoder logic is unrelated to this output-only change.
