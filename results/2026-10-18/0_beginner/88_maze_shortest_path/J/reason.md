# Task B selection: 88_maze_shortest_path / J

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.ijs`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37.

- L3: `  flat =. ,maze` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  start =. flat i.'S'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  goal =. flat i.'G'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  parent =. (#flat)$_1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  parent =. start start}parent` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  queue =. ,start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  head =. 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  steps =. 4 2$_1 0 1 0 0 _1 0 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  while. (head<#queue)*._1=goal{parent do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    current =. head{queue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    head =. >:head` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    row =. <.current%13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    column =. 13|current` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    for_step. steps do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `      'dr dc' =. step` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      nr =. row+dr` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `      nc =. column+dc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `      if. (nr>:0)*.(nr<9)*.(nc>:0)*.nc<13 do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        neighbor =. (nr*13)+nc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        if. ('#'~:neighbor{flat)*._1=neighbor{parent do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `          parent =. current neighbor}parent` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `          queue =. queue,neighbor` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `      end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `    end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `  count =. 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `  current =. goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `  while. current~:start do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    if. '.'=current{flat do. flat =. '*' current}flat end.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    current =. current{parent` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    count =. >:count` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `  smoutput 'steps: ',":count` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `  smoutput 9 13$flat` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **395 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 263 tokens. The contiguous original span L3–L37 costs 395 tokens; the complete original source costs 508 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 387 tokens; removes `flat =. ,maze` from the dependency chain described above.
- Without L4: 383 tokens; removes `start =. flat i.'S'` from the dependency chain described above.
- Without L5: 383 tokens; removes `goal =. flat i.'G'` from the dependency chain described above.
- Without L6: 382 tokens; removes `parent =. (#flat)$_1` from the dependency chain described above.
- Without L7: 384 tokens; removes `parent =. start start}parent` from the dependency chain described above.
- Without L8: 387 tokens; removes `queue =. ,start` from the dependency chain described above.
- Without L9: 388 tokens; removes `head =. 0` from the dependency chain described above.
- Without L10: 368 tokens; removes `steps =. 4 2$_1 0 1 0 0 _1 0 1` from the dependency chain described above.
- Without L11: 376 tokens; removes `while. (head<#queue)*._1=goal{parent do.` from the dependency chain described above.
- Without L12: 386 tokens; removes `current =. head{queue` from the dependency chain described above.
- Without L13: 387 tokens; removes `head =. >:head` from the dependency chain described above.
- Without L14: 384 tokens; removes `row =. <.current%13` from the dependency chain described above.
- Without L15: 385 tokens; removes `column =. 13|current` from the dependency chain described above.
- Without L16: 385 tokens; removes `for_step. steps do.` from the dependency chain described above.
- Without L17: 383 tokens; removes `'dr dc' =. step` from the dependency chain described above.
- Without L18: 385 tokens; removes `nr =. row+dr` from the dependency chain described above.
- Without L19: 385 tokens; removes `nc =. column+dc` from the dependency chain described above.
- Without L20: 366 tokens; removes `if. (nr>:0)*.(nr<9)*.(nc>:0)*.nc<13 do.` from the dependency chain described above.
- Without L21: 380 tokens; removes `neighbor =. (nr*13)+nc` from the dependency chain described above.
- Without L22: 372 tokens; removes `if. ('#'~:neighbor{flat)*._1=neighbor{parent do.` from the dependency chain described above.
- Without L23: 382 tokens; removes `parent =. current neighbor}parent` from the dependency chain described above.
- Without L24: 384 tokens; removes `queue =. queue,neighbor` from the dependency chain described above.
- Without L25: 391 tokens; removes `end.` from the dependency chain described above.
- Without L26: 391 tokens; removes `end.` from the dependency chain described above.
- Without L27: 392 tokens; removes `end.` from the dependency chain described above.
- Without L28: 392 tokens; removes `end.` from the dependency chain described above.
- Without L29: 388 tokens; removes `count =. 0` from the dependency chain described above.
- Without L30: 388 tokens; removes `current =. goal` from the dependency chain described above.
- Without L31: 386 tokens; removes `while. current~:start do.` from the dependency chain described above.
- Without L32: 368 tokens; removes `if. '.'=current{flat do. flat =. '*' current}flat end.` from the dependency chain described above.
- Without L33: 386 tokens; removes `current =. current{parent` from the dependency chain described above.
- Without L34: 387 tokens; removes `count =. >:count` from the dependency chain described above.
- Without L35: 392 tokens; removes `end.` from the dependency chain described above.
- Without L36: 382 tokens; removes `smoutput 'steps: ',":count` from the dependency chain described above.
- Without L37: 385 tokens; removes `smoutput 9 13$flat` from the dependency chain described above.
