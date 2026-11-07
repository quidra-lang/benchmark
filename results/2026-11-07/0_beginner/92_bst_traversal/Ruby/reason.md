The inorder item expression already captures an integer key value rather than a live node. Retain the returned/result list before deletion and print it later; node-key replacement cannot change those previously stored scalar values. No whole-tree copy or changed per-item capture is needed.

left+[node.key]+right constructs an Array of Integer values. Save traverse(root,"inorder") before deletion instead of immediately joining it; Ruby Integer values are immutable and are not node references.

The inorder append/return and node mutation on deletion establish scalar capture. A complete tree copy would add implementation unrelated to preserving an already returned integer list.
