Sort coordinates by x then y and traverse that sorted order backwards for the upper chain, beginning (8,4), then (7,-1). At each new point, repeatedly remove the last chain point while at least two points exist and cross(last-but-one,last,current)<=0; append the current point after those removals. This reverses coordinate order, not the original input sequence.

The compareTo pair orders coordinates, points.reversed supplies the upper source and chain creates a fresh result List. The while guard and removeLast/add implement repeated turn correction; the call also trims its final duplicate endpoint.

Coordinate sorting, reverse traversal, cross product and repeated pop/append establish upper-chain order and rejection. Hull display is unnecessary for the first two upper-chain candidates.
