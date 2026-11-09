Hello, World! encodes to "SGVsbG8sIFdvcmxkIQ==" and becomes "SGVsbG8sIFdvcmxkIQ" when padding is omitted; the quoted line is ""Hello, World!" -> "SGVsbG8sIFdvcmxkIQ"". Its last one-byte group keeps the zero-filled packing but drops two emitted = characters. Man has a complete group (TWFu), while empty input has no groups and stays empty.

bytes.each_slice(3), zero extension, bit packing and six-bit alphabet lookup precede concatenation. Remove only the "="*(3-size) suffix; keep size+1 actual symbols and the quoted output.

ASCII-byte extraction, three-byte zero filling, six-bit index/alphabet lookup, padding branches and quoted output are needed for unpadded encoding. Decoder logic is unrelated to this output-only change.
