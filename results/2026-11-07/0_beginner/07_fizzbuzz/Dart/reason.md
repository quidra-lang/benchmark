The numeric fallback uses the current iteration variable at input 1. It resolves to the surrounding loop binding, rather than to any literal Fizz, Buzz or FizzBuzz result string.

print(number) resolves number to the local declared in the enclosing for initializer; branch bodies are unnecessary for this expression question.

The loop introduces the binding and the fallback expression reads it. The other Fizz/Buzz output branches do not define a competing binding and need no full expansion.
