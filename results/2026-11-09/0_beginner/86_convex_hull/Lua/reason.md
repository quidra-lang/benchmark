Sort coordinates by x then y and traverse that sorted order backwards for the upper chain, beginning (8,4), then (7,-1). At each new point, repeatedly remove the last chain point while at least two points exist and cross(last-but-one,last,current)<=0; append the current point after those removals. This reverses coordinate order, not the original input sequence.

The explicit comparator sorts x then y in place; reversed is built from that sorted table. The chain loop, integer cross formula and remove/append establish upper construction independently of later endpoint removal.

Coordinate sorting, reverse traversal, cross product and repeated pop/append establish upper-chain order and rejection. Hull display is unnecessary for the first two upper-chain candidates.
