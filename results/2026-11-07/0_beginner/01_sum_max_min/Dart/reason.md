Both occurrences of 5 contribute to the sum. Ruby and Dart positions are 3 and 6, while Lua positions are 4 and 7. Iteration is positional, so equal values are not deduplicated.

List.reduce starts with the first value and combines each subsequent value through the last index, incrementing by one; (a, b) => a + b counts both 5 entries.

The literal positions and positional traversal establish both occurrences of 5; the sum operand is sufficient without retaining unrelated maximum/minimum output.
