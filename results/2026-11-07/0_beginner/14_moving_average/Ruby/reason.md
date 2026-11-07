Use the positive named window size for the complete-window starting bound, every included sale and the real-number divisor. With w=5 the six complete windows end on days 5 through 10; with w=11 none exist, so detect that case once and print "no complete window" instead of per-day output.

each_cons(window_size) already generates only full windows; with_index(window_size) labels their ending days. fdiv(window_size) preserves fractions. Guard the empty-window case before traversal.

Window start/end bounds, included-sale aggregation, divisor and output connect w to every required change. Keeping only the average expression would miss the no-complete-window case.
