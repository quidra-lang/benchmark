Rename the loop binding n to term_number and every reference to that binding in the condition, factorial multiplication and printed factorial label. The punctuation "! = " is literal text and the accumulator name is independent.

The for initializer, bound and advancement as well as the if, multiplication and interpolation all use n. factorial remains the accumulator.

Only occurrences bound to the factorial loop variable are relevant to this rename. The accumulator declaration and unrelated literal labels need no expansion once those binding uses are visible.
