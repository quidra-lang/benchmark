Capture the elimination factor 2/4=0.5 before replacing the next row column-k entry. Updating that entry makes it zero, so recomputing the factor afterwards would incorrectly give zero and leave later coefficients unreduced. Reuse the captured factor for every subsequent entry in that row.

final f captures the division before j=k starts writing a[i][j]. The final scalar double value stays 0.5 even when its source cell becomes zero.

The factor capture and subsequent coefficient updates establish why the old pivot-column value must survive. Back substitution and root formatting cannot repair a factor recomputed after zeroing.
