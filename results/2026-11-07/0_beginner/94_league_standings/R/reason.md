# Task B: 94_league_standings / R

The standings order must have its own ordering storage if the original sequence must remain available. Sharing unchanged team records between those two order containers is safe; sharing/reordering the container itself loses the original sequence. Inspect the sort operation rather than recomputing statistics.

order(...) returns a separate permutation and leaves teams/records intact. Keep that permutation separate from the original ordering; no copying of individual team statistics is needed.

Evidence is from `main.R`, L1,L2,L31.

- L1: `teams <- c("Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears")`
- L2: `records <- matrix(0, 6, 7, dimnames = list(teams, c("played", "wins", "draws", "losses", "gf", "ga", "points")))`
- L31: `ordered <- order(-records[, "points"], -differences, -records[, "gf"], teams, method = "radix")`

Minimization: The original ordering binding and actual standings sort are sufficient to distinguish order storage from record sharing. Score updates and table rendering are outside this expression-level question. The selected complete original lines, in source order, cost 143 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 746, and the complete source costs 951. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
