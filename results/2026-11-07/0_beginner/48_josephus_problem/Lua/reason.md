Keep elimination unchanged and render one line as "n=N k=K: P1 P2 ... Pn | survivor=SS". Reuse the case values and removal-order list, join its elements with single spaces, read the final element, pad that decimal survivor to two digits and emit only one terminating newline.

The one format expression contains both existing lines, table.concat(removed," ") and removed[#removed]. Replace the internal newline/label with the required separator and use %02d for the last argument.

The output sites identify the case values, elimination sequence and survivor. Unchanged elimination logic is unnecessary except where Dart currently streams removals and therefore needs the retained-list/output connection.
