Compute the union cardinality from distinct result elements and add it only when emitting the union line. The unit is one distinct integer, regardless of its value, duplicate input slots or the sum of values. Other set-result output remains unchanged.

union = a | b creates the Set and the union hash entry binds it to result at the common output site. Use result.size/length only for label union; sorting/joining is presentation, not cardinality.

The union value and union-line output locate the cardinality suffix. Intersection/difference computations need not be expanded because the change does not consume them.
