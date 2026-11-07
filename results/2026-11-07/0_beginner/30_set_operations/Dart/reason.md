Compute the union cardinality from distinct result elements and add it only when emitting the union line. The unit is one distinct integer, regardless of its value, duplicate input slots or the sum of values. Other set-result output remains unchanged.

The named union is stored as the first result and labels[0] is union. The loop obtains a distinct values list; use union.length or values.length on that first output iteration, not a numeric reduction.

The union value and union-line output locate the cardinality suffix. Intersection/difference computations need not be expanded because the change does not consume them.
