# Task B selection: 84_sales_csv_summary / Go

## Common answer requirements

Trace north sales and notebook quantities; establish independent money and quantity accumulators; explain regional descending-sales/name tie ordering versus product ascending-name ordering.

## Answer and source dependencies

North receives 10×200 = 2000, 8×150 = 1200 and 20×80 = 1600, totaling 4800. Notebook quantities are 10 + 9 + 6 = 25 across north/east/south; unit prices do not enter that quantity sum. Parsing identifies quantity and price separately, computes their product only for sales, and accumulates money by region and raw quantities by product in separate maps/arrays. Regions sort by decreasing money total, with ascending name ties; products sort by name ascending, regardless of their quantity totals. Stable grading after initially alphabetizing names also supplies the regional name tie-break.



## Scope and dependency evidence checked after independent review

Associate the relevant CSV literals with the sequence actually split into fields (including C lines[i]→line copy). Finish aggregation before ranking/output. The add helper must update an existing entry as well as a newly initialized one; its search ends before new-entry fallback. Comparator branches finish before lexical fallback, and comparator/helper definitions finish before use. These dependencies give north sales10×200+8×150+20×80=4800 and notebook quantity10+9+6=25; regional ranking is sales descending then name ascending, while products use alphabetical order.

Source: `main.go`. Selected original locations: L11,L13,L14,L15,L16,L18,L19,L20,L21,L22,L24,L25,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L43,L44,L45,L46,L47.

- L11: `	lines := []string{"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `		"2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `		"2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `		"2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `	regions, products, days := map[string]int{}, map[string]int{}, map[string]int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `	for _, line := range lines[1:] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `		fields := strings.Split(line, ",")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `		quantity, _ := strconv.Atoi(fields[3])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `		price, _ := strconv.Atoi(fields[4])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `		amount := quantity * price` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `		regions[fields[1]] += amount` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `		products[fields[2]] += quantity` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `	regionNames := []string{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `	for name := range regions {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `		regionNames = append(regionNames, name)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `	sort.Slice(regionNames, func(i, j int) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `		a, b := regionNames[i], regionNames[j]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `		if regions[a] != regions[b] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `			return regions[a] > regions[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `		return a < b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `	})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `	productNames := []string{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `	for name := range products {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `		productNames = append(productNames, name)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `	sort.Strings(productNames)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **593 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 576 tokens. The contiguous original span L11–L47 costs 760 tokens; the complete original source costs 974 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L11: 545 tokens; removes `lines := []string{"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",` from the dependency chain described above.
- Without L13: 519 tokens; removes `"2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",` from the dependency chain described above.
- Without L14: 519 tokens; removes `"2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",` from the dependency chain described above.
- Without L15: 543 tokens; removes `"2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"}` from the dependency chain described above.
- Without L16: 556 tokens; removes `regions, products, days := map[string]int{}, map[string]int{}, map[string]int{}` from the dependency chain described above.
- Without L18: 573 tokens; removes `for _, line := range lines[1:] {` from the dependency chain described above.
- Without L19: 575 tokens; removes `fields := strings.Split(line, ",")` from the dependency chain described above.
- Without L20: 574 tokens; removes `quantity, _ := strconv.Atoi(fields[3])` from the dependency chain described above.
- Without L21: 574 tokens; removes `price, _ := strconv.Atoi(fields[4])` from the dependency chain described above.
- Without L22: 581 tokens; removes `amount := quantity * price` from the dependency chain described above.
- Without L24: 580 tokens; removes `regions[fields[1]] += amount` from the dependency chain described above.
- Without L25: 580 tokens; removes `products[fields[2]] += quantity` from the dependency chain described above.
- Without L27: 590 tokens; removes `}` from the dependency chain described above.
- Without L28: 582 tokens; removes `regionNames := []string{}` from the dependency chain described above.
- Without L29: 580 tokens; removes `for name := range regions {` from the dependency chain described above.
- Without L30: 577 tokens; removes `regionNames = append(regionNames, name)` from the dependency chain described above.
- Without L31: 590 tokens; removes `}` from the dependency chain described above.
- Without L32: 570 tokens; removes `sort.Slice(regionNames, func(i, j int) bool {` from the dependency chain described above.
- Without L33: 571 tokens; removes `a, b := regionNames[i], regionNames[j]` from the dependency chain described above.
- Without L34: 575 tokens; removes `if regions[a] != regions[b] {` from the dependency chain described above.
- Without L35: 576 tokens; removes `return regions[a] > regions[b]` from the dependency chain described above.
- Without L36: 589 tokens; removes `}` from the dependency chain described above.
- Without L37: 583 tokens; removes `return a < b` from the dependency chain described above.
- Without L38: 589 tokens; removes `})` from the dependency chain described above.
- Without L43: 582 tokens; removes `productNames := []string{}` from the dependency chain described above.
- Without L44: 580 tokens; removes `for name := range products {` from the dependency chain described above.
- Without L45: 577 tokens; removes `productNames = append(productNames, name)` from the dependency chain described above.
- Without L46: 590 tokens; removes `}` from the dependency chain described above.
- Without L47: 584 tokens; removes `sort.Strings(productNames)` from the dependency chain described above.
