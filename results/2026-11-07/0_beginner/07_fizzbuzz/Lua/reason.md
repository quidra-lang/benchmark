The numeric fallback uses the current iteration variable at input 1. It resolves to the surrounding loop binding, rather than to any literal Fizz, Buzz or FizzBuzz result string.

The %d argument n resolves to the numeric for control variable, initialized to 1; literal result-string branches are unnecessary.

The loop introduces the binding and the fallback expression reads it. The other Fizz/Buzz output branches do not define a competing binding and need no full expansion.
