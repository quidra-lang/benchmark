Preserve the original ordering container and create a separate standings order, while allowing both to refer to the same team records. Copying the outer ordering is enough because this requirement concerns sort order rather than independent mutable statistics.

teams.sort_by returns a new ordered Array without reordering teams, so the current expression already satisfies the requirement. The block reads shared stats records only.

The team ordering construction and sort site establish which outer container must be copied. Updating match statistics is unaffected because shared team records are allowed.
