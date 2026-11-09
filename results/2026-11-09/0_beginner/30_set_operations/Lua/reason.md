Compute the union cardinality from distinct result elements and add it only when emitting the union line. The unit is one distinct integer, regardless of its value, duplicate input slots or the sum of values. Other set-result output remains unchanged.

all is a key-set built from a and b; each key appends once to results[1]. Count #results[1], not #all (a sparse numeric-key table) or the original inputs, and insert the size at the i=1 output path.

The union value and union-line output locate the cardinality suffix. Intersection/difference computations need not be expanded because the change does not consume them.
