The final remaining>1 decision appends the residual integer as one factor even when trial division collected none. For prime input 9973 the unchanged residual is 9973 and is appended; a residual 1 fails the strict comparison and is omitted.

The one-line if combines remaining>1 with appending tostring(remaining); neither trial loops nor final formatting affect this fact.

The residual initialization/update and final strict greater-than-one append establish prime and residual-one behavior. Formatting the factor list does not determine whether the residual is inserted.
