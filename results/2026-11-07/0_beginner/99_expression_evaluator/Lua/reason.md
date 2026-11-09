At this assignment the prior height is 7. The parser first evaluates 100 divided by the parenthesized height-7; recursive expression evaluation makes that denominator 0. The division-by-zero guard raises before the outer + can request its right term, so bonus is never looked up. Assignment commits only after successful evaluation, retaining height=7 and printing "error: division by zero".

The recursive factor/term/expression closures share position and variables. term checks zero immediately after its right factor and error aborts before expression advances to bonus. pcall returns failure, so the error branch runs instead of assignment. Tokenizer implementation is unnecessary because the question begins from token input.

Assignment evaluation/commit, division guard and left-to-right expression evaluation establish the exception before bonus lookup. The retained height initialization proves assignment failure preserves seven.
