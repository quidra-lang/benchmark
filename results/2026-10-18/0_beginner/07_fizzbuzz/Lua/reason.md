# Task B selection: 07_fizzbuzz / Lua

## Common answer requirements

1. Explain selection of FizzBuzz for both 15 and 30 when divisibility by 3 and 5 holds.
2. Show why the selected control flow or composed string emits one complete line rather than competing outputs.

## Answer supported by the excerpt

Both 15 and 30 have remainder zero modulo 15, so the first branch of the mutually exclusive chain wins and later divisibility branches are skipped. In the composed-string implementations, the true divisibility tests contribute Fizz and Buzz to one concatenated string, and one print call emits that string. No separate Fizz or Buzz line is emitted for these cases.

## Source evidence and dependencies

Selected `main.lua` lines: 2-4,6. The excerpt preserves these complete lines in their original order and indentation.

The selected first matching condition and FizzBuzz output establish the chosen result. The following else/elseif/case clauses establish exclusivity rather than independent if statements. The alternative string-building versions require both the composed expression and its single print call. The question supplies 15 and 30; the surrounding numeric enumeration is unrelated to this decision.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. The FizzBuzz literal alone does not establish when it is selected or why the shorter outputs are skipped. Selecting every branch body would add outputs that cannot run for the two given inputs. The retained branch boundaries or the single string-composition site support all requested facts.

The selected excerpt contains **60 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 73 tokens; the complete source contains 130 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
