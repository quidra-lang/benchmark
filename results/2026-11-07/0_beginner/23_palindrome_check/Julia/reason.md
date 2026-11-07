# Task B: 23_palindrome_check / Julia

The original phrase `Step on no pets.` is retained for display. Lowercasing and removing nonletters yields `steponnopets`, whose reverse is the identical letter sequence. The comparison therefore chooses yes, and the completed line is `Step on no pets. -> yes`. Capital S, the spaces and the period remain in the original displayed phrase, not in the comparison copy.

clean is a new lowercase regex-filtered string; its reverse comparison supplies the label, and println interpolates the original phrase.

Evidence is from `main.jl`, L1,L6,L8,L9,L10,L11.

- L1: `phrases = [`
- L6: `"Step on no pets.",`
- L8: `]`
- L9: `for phrase in phrases`
- L10: `clean = filter(c -> 'a' <= c <= 'z', lowercase(phrase))`
- L11: `println(phrase, " -> ", clean == reverse(clean) ? "yes" : "no")`

Minimization: The input literal for this phrase, its local binding, normalization, comparison and output establish separation of display/comparison data. Unrelated phrase literals can be omitted when separately written on other complete lines. The selected complete original lines, in source order, cost 96 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 164, and the complete source costs 166. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
