The per-step counter starts at zero and increments once for each existing element copied one slot right inside the while loop. The extracted value is written to its final slot after the loop, without a counter increment; therefore that final placement is not another shift.

shifts++ follows a[j]=a[j-1] in the while block. The selected closing brace distinguishes the later a[j]=v insertion.

The zeroed counter, right-shift loop and final placement distinguish counted copies from the uncounted insertion. Other passes and final summary formatting are unnecessary.
