# Task B: 26_caesar_cipher / R

The shift operation maps letters within their own uppercase/lowercase alphabet using modulo 26, so Z with shift 3 wraps to C. The following comma is not a letter and is carried through unchanged. The produced ciphertext, not the original message, is supplied to the same operation with shift -3 for decryption.

chartr maps the original upper/lower alphabet to a modulo-shifted alphabet and returns a new character value. The caller binds cipher and supplies it to caesar(cipher,-3).

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L8,L9.

- L1: `caesar <- function(message, shift) {`
- L2: `indices <- (seq_along(letters) - 1 + shift) %% 26 + 1`
- L3: `alphabet <- paste0(c(LETTERS, letters), collapse = "")`
- L4: `shifted <- paste0(c(LETTERS[indices], letters[indices]), collapse = "")`
- L5: `chartr(alphabet, shifted, message)`
- L6: `}`
- L8: `ciphertext <- caesar("Zoe, meet Max by the Old Bridge at six!", 3)`
- L9: `cat(ciphertext, "\n", caesar(ciphertext, -3), "\n", sep = "")`

Minimization: The complete small shift helper is needed because its case/wrap/nonletter behavior is user-defined. The encryption binding and decryption call establish the value crossing that boundary; unrelated printing is omitted where separately written. The selected complete original lines, in source order, cost 180 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 181, and the complete source costs 181. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
