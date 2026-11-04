# Task B selection: 17_number_bases / J

Identify the hex-only edit site and preserve the original decimal, binary and octal fields, labels, order, zero and width rules.

The dyadic base verb is called separately for binary, octal and hex. Apply the standard J lowercase conversion only to the returned value of the 16-base call after hex=. ASCII A–F change case while the characters for zero, digits, and any layout stay intact. No shared conversion logic needs to change.

Complete main.ijs lines: 8. For the J alternative, the shared converter and digit lookup would add dependencies in the other base calls; an output-local conversion needs only the one selected call site. For Julia, the conversion without its consumer would omit the link to hex=; the original input values and loop do not locate the case change. The benchmark tokenizer counts 57 tokens in this excerpt.
