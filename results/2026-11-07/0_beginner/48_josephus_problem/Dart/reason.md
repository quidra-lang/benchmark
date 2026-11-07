Keep elimination unchanged and render one line as "n=N k=K: P1 P2 ... Pn | survivor=SS". Reuse the case values and removal-order list, join its elements with single spaces, read the final element, pad that decimal survivor to two digits and emit only one terminating newline.

StringBuffer writes the header and each removed person incrementally; the named removed list now retains the order and .last supplies survivor. Replace per-item rendering with removed.join(" ") if desired and replace the embedded newline in writeln with the pipe field plus padded last value; stdout.write completes emission.

The output sites identify the case values, elimination sequence and survivor. Unchanged elimination logic is unnecessary except where Dart currently streams removals and therefore needs the retained-list/output connection.
