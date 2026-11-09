The second string encodes as "12W1B12W3B" and decodes to the original twelve-W, B, twelve-W, BBB sequence. The complete line is "WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB". Both arrows have one surrounding space.

chunk(&:itself) forms maximal equal-character runs; scan(/(\d+)([A-Z])/) parses the full two-digit counts from encoded and repeats their letters into decoded. The output uses all three distinct values.

The selected string, run accumulation, multi-digit decode and final interpolation support the full round trip and spacing. Other source strings are not needed for the second case.
