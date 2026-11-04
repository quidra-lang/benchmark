# Task B selection: 17_number_bases / Julia

Identify the hex-only edit site and preserve the original decimal, binary and octal fields, labels, order, zero and width rules.

The uppercase call wraps only the base-16 conversion. Its result is the hex interpolation, while the adjacent base-2 and base-8 calls go straight to the output. Drop uppercase; Julia’s base-16 string conversion already returns lowercase letters.

Complete main.jl lines: 2, 3. For the J alternative, the shared converter and digit lookup would add dependencies in the other base calls; an output-local conversion needs only the one selected call site. For Julia, the conversion without its consumer would omit the link to hex=; the original input values and loop do not locate the case change. The benchmark tokenizer counts 70 tokens in this excerpt.
