The numeric fallback uses the current iteration variable at input 1. It resolves to the surrounding loop binding, rather than to any literal Fizz, Buzz or FizzBuzz result string.

puts n resolves n to the |n| parameter of the (1..30).each block. The divisibility branches do not affect this name-resolution fact.

The loop introduces the binding and the fallback expression reads it. The other Fizz/Buzz output branches do not define a competing binding and need no full expansion.
