For hanoi(4,A,C,B), solve (3,A,B,C), emit disk 4 from A to C, then solve (3,B,C,A). The zero-disk base emits no move. Reassigning parameter roles in recursive calls does not rebind caller peg names or mutate shared peg storage; fifteen moves result.

The first recursive result plus one plus the second result combines counts. Local parameters receive label references but no label mutation occurs; the only effect is puts.

The base test, ordered recursive calls, move emission and four-disk invocation establish call-role rebinding and fifteen moves. No explicit peg-container implementation is needed because the source passes peg labels.
