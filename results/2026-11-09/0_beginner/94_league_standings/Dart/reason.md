Preserve the original ordering container and create a separate standings order, while allowing both to refer to the same team records. Copying the outer ordering is enough because this requirement concerns sort order rather than independent mutable statistics.

teams.values.toList() creates a new ordering List before the cascade sort mutates it. The insertion order of the teams Map remains intact; contained Team objects are shared intentionally, so no change is needed.

The team ordering construction and sort site establish which outer container must be copied. Updating match statistics is unaffected because shared team records are allowed.
