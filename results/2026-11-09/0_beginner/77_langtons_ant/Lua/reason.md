Preserve turn and color inversion first, then compute an unwrapped proposed coordinate and commit it only if both coordinates are within the board. An upward proposal from row 0 gives row -1, so reject movement and keep the old row/column while retaining the new direction and flipped current cell.

direction+1 selects the physical direction tuple. Replace %11 coordinate writes with unwrapped proposals and one bounds check for 0..10; commit both together only when valid.

The turn, flip, proposed movement and modulo update establish the order that must be preserved while replacing wrap with bounds validation. Board rendering cannot affect the rejected move.
