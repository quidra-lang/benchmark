At 506 yen, denomination 500 yields count 1 and remainder 6, appending 500x1 and adding one piece. Denomination 100 then yields count 0 and remainder 6, so no item appears and the piece total gains zero. The original amount still labels the line as 506 yen.

remaining ~/ denom and %= denom consume change, total += count adds zero for the skipped denomination, and count>0 controls only the item. amount is printed before remaining changes.

The original amount, denomination order, quotient/remainder updates and conditional append connect 506 to 500x1 and the skipped 100 entry. Other input amounts are unrelated.
