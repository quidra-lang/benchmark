Zero item-stage and zero-capacity states start at value 0. The first tent (weight 10,value 120) cannot improve capacity below 10 and improves capacity 10 using prior-stage zero plus 120. Every take candidate reads the preceding item row, so the same item cannot be selected twice. Traceback detects stage differences, subtracts chosen weight and emits selected names in original item order.

The zero-filled table, i-1 transition and descending traceback establish stage dependencies. chosen collects backwards, reverse! restores order and map(&:first) chooses names.

Base DP storage, item-stage/capacity loops, preceding-row take candidate and traceback/output establish both 0/1 choice and selected-name order. Keeping only final optimum output would miss item reuse prevention.
