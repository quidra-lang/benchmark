# Task B selection: 07_fizzbuzz / C#

The numeric fallback reads the loop variable n, initially 1. Its integer output/conversion reference resolves to that loop binding, whereas Fizz, Buzz and FizzBuzz are literal text results rather than names resolving to integer storage.

The loop introduction and numeric fallback identify the binding and reference. Divisibility decisions do not need to be retraced to answer this name-resolution question.

Selected complete source lines in `Program.cs`: 4, 9. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
