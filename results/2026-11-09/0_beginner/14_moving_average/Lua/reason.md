Use the positive named window size for the complete-window starting bound, every included sale and the real-number divisor. With w=5 the six complete windows end on days 5 through 10; with w=11 none exist, so detect that case once and print "no complete window" instead of per-day output.

The day loop begins at window_size and ends at #sales; replace the fixed three-term addition with a sum over day-window_size+1 through day. / window_size and %.2f remain real division and display.

Window start/end bounds, included-sale aggregation, divisor and output connect w to every required change. Keeping only the average expression would miss the no-complete-window case.
