The inorder item expression already captures an integer key value rather than a live node. Retain the returned/result list before deletion and print it later; node-key replacement cannot change those previously stored scalar values. No whole-tree copy or changed per-item capture is needed.

The inorder branch appends node.value, a numeric scalar, into a separate result table. Keep that table beyond the current loop iteration and delay table.concat output; later node.value assignment does not alter saved numbers.

The inorder append/return and node mutation on deletion establish scalar capture. A complete tree copy would add implementation unrelated to preserving an already returned integer list.
