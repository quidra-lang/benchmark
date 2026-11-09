The per-step counter starts at zero and increments once for each existing element copied one slot right inside the while loop. The extracted value is written to its final slot after the loop, without a counter increment; therefore that final placement is not another shift.

The copy and shifts=shifts+1 are inside while; the end before numbers[j+1]=value establishes that the final extracted-value write does not add a shift.

The zeroed counter, right-shift loop and final placement distinguish counted copies from the uncounted insertion. Other passes and final summary formatting are unnecessary.
