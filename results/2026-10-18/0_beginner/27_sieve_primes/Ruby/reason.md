# Task B selection: 27_sieve_primes / Ruby

## Common answer requirements

Explain initial primality of 7 and 49, how marking reaches 49 through p=7, why p itself is never crossed out, and how the resulting flags control membership in printed primes.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The initial table sets both 7 and 49 true. Processing p starts at 2 and considers true flags; marking starts at 2p and advances by p, so no prime marks itself. The smaller primes 2, 3, and 5 do not divide 7 or 49. At p=7 the multiples 14,21,28,35,42,49 are marked false. Hence 7 stays true and 49 becomes false. Output derives prime values from true flags and prints those values, retaining 7 and omitting 49.

The end of the prime-marking loop places selection and output after every sieving prime has processed its multiples.

Source: `main.rb`. Selected original lines: 1,2,4,5,6,7,9. The following original-line dependencies support the answer above:

- L1: `limit = 200` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L2: `is_prime = Array.new(limit + 1, true)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L4: `(2..limit).each do |n|` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L5: `  (n * 2).step(limit, n) { |multiple| is_prime[multiple] = false } if is_prime[n]` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L6: `end` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L7: `primes = (2..limit).select { |n| is_prime[n] }` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L9: `primes.each_slice(10) { |row| puts row.join(' ') }` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.

## Minimization and semantics

The selected excerpt measures **145 tokens** with `metric/tokenizer.py` `tokenize`; the complete original source is a sufficient alternative of **179 tokens**. Complete original lines and their order are preserved, and no source location is repeated. Excerpts are evidence fragments and need not compile independently. Standard arithmetic, collection, regex, formatting and iteration operations use their language/library semantics. User helper behavior is established by its retained operations.

The smaller deletion alternatives below were measured. Each drops the identified dependency or boundary from this concrete answer. This review establishes a sufficient minimized dependency set, without claiming a global mathematical minimum.

- Without L1: 137 tokens (versus 145); removes `limit = 200`.
- Without L2: 125 tokens (versus 145); removes `is_prime = Array.new(limit + 1, true)`.
- Without L4: 131 tokens (versus 145); removes `(2..limit).each do |n|`.
- Without L5: 100 tokens (versus 145); removes `(n * 2).step(limit, n) { |multiple| is_prime[multiple] = false } if is_prime[n]`.
- Without L6: 143 tokens (versus 145); removes `end`.
- Without L7: 118 tokens (versus 145); removes `primes = (2..limit).select { |n| is_prime[n] }`.
- Without L9: 116 tokens (versus 145); removes `primes.each_slice(10) { |row| puts row.join(' ') }`.
