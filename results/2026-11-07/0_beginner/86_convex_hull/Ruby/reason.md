Sort coordinates by x then y and traverse that sorted order backwards for the upper chain, beginning (8,4), then (7,-1). At each new point, repeatedly remove the last chain point while at least two points exist and cross(last-but-one,last,current)<=0; append the current point after those removals. This reverses coordinate order, not the original input sequence.

points.sort supplies lexicographic array-coordinate order; upper receives ordered.reverse. chain has fresh result storage and uses cross plus pop/append; no hull concatenation or area code is needed.

Coordinate sorting, reverse traversal, cross product and repeated pop/append establish upper-chain order and rejection. Hull display is unnecessary for the first two upper-chain candidates.
