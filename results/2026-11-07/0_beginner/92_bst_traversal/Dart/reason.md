The inorder item expression already captures an integer key value rather than a live node. Retain the returned/result list before deletion and print it later; node-key replacement cannot change those previously stored scalar values. No whole-tree copy or changed per-item capture is needed.

traverse returns List<int> and mode==0 inserts node.key as an int. Retain that List<int> instead of immediate join; replacing a mutable Node.key cannot affect the independent list entries.

The inorder append/return and node mutation on deletion establish scalar capture. A complete tree copy would add implementation unrelated to preserving an already returned integer list.
