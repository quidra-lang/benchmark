# Task B selection: 88_maze_shortest_path / Quidra

Explain how first discovering the goal leads to reconstructing and printing the marked route.

The flattened maze locates S and G by their symbols. The FIFO queue visits cells by distance, and each passable, previously undiscovered neighbor receives the current cell as its parent before it is enqueued. The search stops after the goal has a parent. Reconstruction starts at that goal and follows one parent edge per iteration until the start. The step count therefore equals route edges, one less than route cells. Only dots are replaced by asterisks: G fails that test and S is the stopping point. Consecutive chunks restore the original thirteen-column rows for output.

The selected endpoint definitions, parent initialization, discovery guards and assignments, complete reconstruction and output operations establish that chain. The concrete maze rows are unnecessary for this explanation of the source path. `Queue.take`, `index`, `characters` and `chunks` use documented package semantics; their implementations are not source dependencies.

Selected complete source lines in order: 1, 2, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44.

Every selected line is copied verbatim from `main.qui` in source order. The reviewed alternatives were the relevant contiguous span and complete source; each adds unchanged context. This is a reviewed sufficient selection, not a proof of a global minimum. Task B assumes Task A correctness as required by the benchmark README.

Task A uses 584 tokens. Task B uses 467 tokens under the unchanged `metric/tokenizer.py`. Source selection and token measurement do not establish compilation or execution.
