# Task B: 23_palindrome_check / R

The original phrase `Step on no pets.` is retained for display. Lowercasing and removing nonletters yields `steponnopets`, whose reverse is the identical letter sequence. The comparison therefore chooses yes, and the completed line is `Step on no pets. -> yes`. Capital S, the spaces and the period remain in the original displayed phrase, not in the comparison copy.

clean is a new utf8ToInt vector of the lowercase filtered letters; identical(clean,rev(clean)) supplies the label while sprintf still receives phrase.

Evidence is from `main.R`, L1,L3,L4,L5,L6,L7.

- L1: `phrases <- c(`
- L3: `"Step on no pets.", "No lemon, no melon"`
- L4: `)`
- L5: `for (phrase in phrases) {`
- L6: `clean <- utf8ToInt(tolower(gsub("[^A-Za-z]", "", phrase)))`
- L7: `cat(sprintf("%s -> %s\n", phrase, if (identical(clean, rev(clean))) "yes" else "no"))`

Minimization: The input literal for this phrase, its local binding, normalization, comparison and output establish separation of display/comparison data. Unrelated phrase literals can be omitted when separately written on other complete lines. The selected complete original lines, in source order, cost 127 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 179, and the complete source costs 181. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
