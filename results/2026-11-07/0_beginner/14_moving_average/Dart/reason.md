Use the positive named window size for the complete-window starting bound, every included sale and the real-number divisor. With w=5 the six complete windows end on days 5 through 10; with w=11 none exist, so detect that case once and print "no complete window" instead of per-day output.

The zero-based ending index starts at windowSize-1 and labels i+1. Replace the fixed three-term sum with an inclusive window sum, retaining / windowSize and two-digit formatting. An outer size comparison handles w>sales.length once.

Window start/end bounds, included-sale aggregation, divisor and output connect w to every required change. Keeping only the average expression would miss the no-complete-window case.
