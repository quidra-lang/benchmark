# Task B: 76_number_to_words / Julia

71000 becomes `seventy-one thousand`; 300019 becomes `three hundred thousand nineteen`; whole input 0 becomes `zero`. Below-one-thousand zero subparts return empty text and are omitted from composition, rather than injecting zero words. Tens/ones supply the hyphen in seventy-one, while nonempty thousand/remainder components are joined with single spaces.

under_thousand returns empty for a zero subpart; to_words returns "zero" only for whole input zero, filters empty components and joins them.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L19,L20,L21,L22,L23,L24,L25.

- L1: `function small_words(number)`
- L2: `units = split(`
- L3: `"zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen",`
- L4: `)`
- L5: `tens = split("zero ten twenty thirty forty fifty sixty seventy eighty ninety")`
- L6: `parts = String[]`
- L7: `hundreds, remainder = divrem(number, 100)`
- L8: `hundreds > 0 && push!(parts, string(units[hundreds+1], " hundred"))`
- L9: `if remainder >= 20`
- L10: `phrase = String(tens[div(remainder, 10)+1])`
- L11: `remainder%10 > 0 && (phrase *= string("-", units[remainder%10+1]))`
- L12: `push!(parts, phrase)`
- L13: `elseif remainder > 0`
- L14: `push!(parts, units[remainder+1])`
- L15: `end`
- L16: `return join(parts, " ")`
- L19: `function number_words(number)`
- L20: `number == 0 && return "zero"`
- L21: `thousands, remainder = divrem(number, 1000)`
- L22: `parts = String[]`
- L23: `thousands > 0 && push!(parts, string(small_words(thousands), " thousand"))`
- L24: `remainder > 0 && push!(parts, small_words(remainder))`
- L25: `return join(parts, " ")`

Minimization: The small-number helper, thousand composition and named final word result are needed for these three cases. Other input literals and numeric-prefix output are not necessary to derive the word expressions. The selected complete original lines, in source order, cost 394 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 397, and the complete source costs 480. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
