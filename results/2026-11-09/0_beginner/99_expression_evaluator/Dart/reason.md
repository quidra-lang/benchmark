At this assignment the prior height is 7. The parser first evaluates 100 divided by the parenthesized height-7; recursive expression evaluation makes that denominator 0. The division-by-zero guard raises before the outer + can request its right term, so bonus is never looked up. Assignment commits only after successful evaluation, retaining height=7 and printing "error: division by zero".

The typed parser holds the existing Map and position. unary delegates to primary, parentheses recurse and term throws EvaluationError for right==0 before the outer additive term. The try block assigns only after parser.expression succeeds; catch emits the message field. No bonus lookup or other-line execution is required.

Assignment evaluation/commit, division guard and left-to-right expression evaluation establish the exception before bonus lookup. The retained height initialization proves assignment failure preserves seven.
