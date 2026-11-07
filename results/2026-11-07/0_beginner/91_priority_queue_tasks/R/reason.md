# Task B: 91_priority_queue_tasks / R

Use (priority,ascending task name) for every heap comparison instead of (priority,insertion sequence), including both sift directions and the final repeated removals. The revised run lines are `run: deploy (priority 1)`, `run: test (priority 2)`, `run: email (priority 3)`, `run: review (priority 2)`, `run: build (priority 1)`, `run: lint (priority 3)`. Final output is `remaining: report docs backup cleanup`. Parse priorities as numbers and retain names as text; the remaining list must be drained under the same comparator, not sorted by the old insertion rule.

Change before's equal-priority comparison from sequence to name; both heap helpers call it, and draining through heap_pop preserves that order.

Evidence is from `main.R`, L1,L3,L4,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54.

- L1: `before <- function(a, b) a$priority < b$priority || (a$priority == b$priority && a$sequence < b$sequence)`
- L3: `heap <- new.env(parent = emptyenv())`
- L4: `heap$items <- list()`
- L6: `heap_push <- function(task) {`
- L7: `items <- heap$items`
- L8: `items[[length(items) + 1]] <- task`
- L9: `child <- length(items)`
- L10: `while (child > 1) {`
- L11: `parent <- child %/% 2`
- L12: `if (!before(items[[child]], items[[parent]])) break`
- L13: `items[c(child, parent)] <- items[c(parent, child)]`
- L14: `child <- parent`
- L15: `}`
- L16: `heap$items <- items`
- L17: `}`
- L19: `heap_pop <- function() {`
- L20: `items <- heap$items`
- L21: `task <- items[[1]]`
- L22: `last <- tail(items, 1)[[1]]`
- L23: `items <- head(items, -1)`
- L24: `if (length(items) > 0) {`
- L25: `items[[1]] <- last`
- L26: `parent <- 1`
- L27: `while (2 * parent <= length(items)) {`
- L28: `child <- 2 * parent`
- L29: `if (child < length(items) && before(items[[child + 1]], items[[child]])) child <- child + 1`
- L30: `if (!before(items[[child]], items[[parent]])) break`
- L31: `items[c(child, parent)] <- items[c(parent, child)]`
- L32: `parent <- child`
- L33: `}`
- L34: `}`
- L35: `heap$items <- items`
- L36: `task`
- L37: `}`
- L39: `operations <- c(`
- L40: `"add email 3", "add backup 5", "add deploy 1", "run", "add report 3", "add test 2", "add lint 3",`
- L41: `"run", "run", "add cleanup 5", "add review 2", "run", "add build 1", "add docs 4", "run", "run"`
- L42: `)`
- L43: `for (sequence in seq_along(operations)) {`
- L44: `parts <- strsplit(operations[sequence], " ", fixed = TRUE)[[1]]`
- L45: `if (parts[1] == "add") {`
- L46: `heap_push(list(name = parts[2], priority = as.integer(parts[3]), sequence = sequence))`
- L47: `} else {`
- L48: `task <- heap_pop()`
- L49: `cat(sprintf("run: %s (priority %d)\n", task$name, task$priority))`
- L50: `}`
- L51: `}`
- L52: `remaining <- character(0)`
- L53: `while (length(heap$items) > 0) remaining <- c(remaining, heap_pop()$name)`
- L54: `cat("remaining: ", paste(remaining, collapse = " "), "\n", sep = "")`

Minimization: The comparator, both custom heap helpers, sixteen operations, parser/entry representation, run output and final drain are needed. This end-to-end dependency covers the substantive program without relying on a generic full-source fallback. The selected complete original lines, in source order, cost 829 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 833, and the complete source costs 833. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
