# Task B: 85_text_justify / Julia

Splitting only on word-separating spaces retains punctuation: `names,` is one six-character token, including its comma. Greedy packing accepts a word only when letter lengths plus at least one space per existing gap fit width 30; otherwise it closes the current line and starts a fresh one. For a nonfinal multiword line, total spaces=30-sum(word lengths), gaps=word count-1, base=spaces quotient gaps, extra=spaces remainder gaps. Every gap receives base spaces and the leftmost extra gaps one more, giving exactly 30 characters. Vertical bars frame the completed text. Final/single-word lines instead join with ordinary single spaces and pad on the right to width 30.

split(paragraph) retains comma punctuation; letters plus length(current) accounts for minimal new gaps. divrem and the IOBuffer loop distribute spaces after each nonfinal word.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31.

- L2: `width = 30`
- L3: `paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week."`
- L4: `lines = Vector{String}[]`
- L5: `current = String[]`
- L6: `letters = 0`
- L7: `for word in split(paragraph)`
- L8: `if !isempty(current) && letters+length(current)+length(word) > width`
- L9: `push!(lines, current)`
- L10: `current = String[]`
- L11: `letters = 0`
- L12: `end`
- L13: `push!(current, word)`
- L14: `letters += length(word)`
- L15: `end`
- L16: `push!(lines, current)`
- L17: `for (number, words) in enumerate(lines)`
- L18: `if number == length(lines) || length(words) == 1`
- L19: `line = rpad(join(words, " "), width)`
- L20: `else`
- L21: `spaces = width-sum(length, words)`
- L22: `base, extra = divrem(spaces, length(words)-1)`
- L23: `output = IOBuffer()`
- L24: `for i in eachindex(words)`
- L25: `print(output, words[i])`
- L26: `i < length(words) && print(output, repeat(" ", base+(i <= extra)))`
- L27: `end`
- L28: `line = String(take!(output))`
- L29: `end`
- L30: `println('|', line, '|')`
- L31: `end`

Minimization: Paragraph/token binding, greedy state transitions, final-line branch, quotient/remainder distribution and framing are necessary for this routine. No individual paragraph line needs a full formatting trace. The selected complete original lines, in source order, cost 511 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 511, and the complete source costs 522. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
