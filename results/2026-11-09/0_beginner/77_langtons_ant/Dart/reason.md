Preserve turn and color inversion first, then compute an unwrapped proposed coordinate and commit it only if both coordinates are within the board. An upward proposal from row 0 gives row -1, so reject movement and keep the old row/column while retaining the new direction and flipped current cell.

d updates before black[r][c] flips; directions[d] supplies the next displacement. Replace both %11 writes with proposed row/column, testing both against 0 and 11 before assignment.

The turn, flip, proposed movement and modulo update establish the order that must be preserved while replacing wrap with bounds validation. Board rendering cannot affect the rejected move.
