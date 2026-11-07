Rename the loop binding n to term_number and every reference to that binding in the condition, factorial multiplication and printed factorial label. The punctuation "! = " is literal text and the accumulator name is independent.

The each block parameter n binds the references in n.positive?, factorial *= n and #{n}; no callable with an independently scoped n appears.

Only occurrences bound to the factorial loop variable are relevant to this rename. The accumulator declaration and unrelated literal labels need no expansion once those binding uses are visible.
