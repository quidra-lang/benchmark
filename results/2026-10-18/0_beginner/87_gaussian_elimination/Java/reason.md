# Task B selection: 87_gaussian_elimination / Java

## Common answer requirements

Locate solution-value formatting; specify exactly six fractional digits with half-up rounding, negative signs and leading zero, leaving all double-precision numerical work untouched.

## Answer and source dependencies

Replace only the four-place output formatter with an explicit decimal half-up formatter producing exactly six fractional digits. Apply decimal rounding to the final solution value, rounding its magnitude at the seventh decimal place, carrying into the integer part when necessary, and restoring the original negative sign even when a negative value rounds to zero. Include a leading integer zero for subunit values and pad the fraction to six digits. Merely setting precision to6 does not establish the requested tie rule for every native formatter. Use an appropriate decimal rounding API or exact decimal-digit procedure; binary floating-point floor(abs(value)*1000000+0.5) is not a universally exact decimal half-up implementation. Leave all elimination, pivot and back-substitution operations in their current floating-point type and order.



## Scope and dependency evidence checked after independent review

The retained original formatter is the only affected change site. Its current four-place precision becomes a six-place presentation with an explicit decimal half-up policy; labels, variable numbering and newlines remain the same. Unchanged numerical algorithms and example inputs do not locate any additional edit.

Source: `Main.java`. Selected original locations: L37.

- L37: `                System.out.printf(Locale.ROOT, "x%d = %.4f%n", i + 1, x[i]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **41 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 41 tokens. The contiguous original span L37–L37 costs 41 tokens; the complete original source costs 853 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L37: 0 tokens; removes `System.out.printf(Locale.ROOT, "x%d = %.4f%n", i + 1, x[i]);` from the dependency chain described above.
