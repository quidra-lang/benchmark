Preserve the original ordering container and create a separate standings order, while allowing both to refer to the same team records. Copying the outer ordering is enough because this requirement concerns sort order rather than independent mutable statistics.

table.sort(teams,...) mutates the original team-name array. Copy it with an outer array copy, sort that new ordering with the same comparator and use it in the standings loop; records can remain shared.

The team ordering construction and sort site establish which outer container must be copied. Updating match statistics is unaffected because shared team records are allowed.
