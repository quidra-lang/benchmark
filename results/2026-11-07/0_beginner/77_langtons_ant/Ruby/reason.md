Preserve turn and color inversion first, then compute an unwrapped proposed coordinate and commit it only if both coordinates are within the board. An upward proposal from row 0 gives row -1, so reject movement and keep the old row/column while retaining the new direction and flipped current cell.

directions supplies offsets after the turn and flip. Replace the two modulo-wrapped assignments with temporary coordinates and a joint 0<=coordinate<size guard; do not place turn/flip inside that guard.

The turn, flip, proposed movement and modulo update establish the order that must be preserved while replacing wrap with bounds validation. Board rendering cannot affect the rejected move.
