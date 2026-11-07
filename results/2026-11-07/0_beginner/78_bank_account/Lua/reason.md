The first withdraw Leo 4000 is operation 2, producing "op 2: withdraw Leo 4000 failed (insufficient funds)". The output expression preserves transaction text, places a space after the colon and before the result, and takes the suffix parentheses from a literal string.

ipairs number is already one-based; %d:%s/%s template fields preserve the transaction and exact failure literal. The two spaces are literal template spaces.

The operation index/source transaction and failure result/output interpolation establish the exact first Leo-withdraw line. Later transactions do not affect that first failure.
