An empty replacement sequence skips the edge loop entirely, so neither a last-to-first access nor an earlier point access is evaluated. There is no explicit rejection and no implicit indexing failure on this path. The initialized area sum 0 and perimeter 0.0 reach formatting, giving polygon 1 area=0.0 perimeter=0.000.

i<points.length is false immediately, so even points[i] is skipped before the wraparound access. The loop-closing brace separates the subsequent default-result print.

Zero accumulators, edge-loop bound, indexed edge operations and output establish the empty-input path. The loop body is needed to show its potentially unsafe indexing is never reached.
