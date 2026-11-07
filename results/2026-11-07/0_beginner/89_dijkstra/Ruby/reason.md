Replace the unreached initializer with 1000, retaining the subsequent source-distance assignment to zero. There are seven vertices and every given edge weight is positive and at most 9; any finite shortest path can be simple with at most six edges, so its distance is at most 54, safely below 1000.

Array.new(names.length,Float::INFINITY) is the default site and distances[0]=0 is separate. The names and edge lines establish the seven-vertex/max-weight bound without relaxation or path rendering.

The literal vertex/edge data, unreachable fill and source-zero assignment establish the replacement sentinel bound. Relaxation arithmetic is retained only where it demonstrates the sentinel participates in comparison.
