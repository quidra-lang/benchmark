source("tac_parser.R")
source("cfg.R")
source("dataflow.R")
source("optimizations.R")
source("regalloc.R")

PASS_ORDER <- c("constprop", "copyprop", "cse", "dce", "licm", "unreachable")
VERSIONS <- c("original", "optimized", "allocated")
comma_list <- function(values) if (!length(values)) "-" else paste0(values, collapse = ",")
block_list <- function(numbers) if (!length(numbers)) "-" else comma_list(paste0("B", numbers))
instruction_list <- function(numbers) if (!length(numbers)) "-" else comma_list(paste0("#", numbers))
read_settings <- function() {
    lines <- readLines("input/params.txt", warn = FALSE)
    enabled <- words_of(lines[2L])[-1L]
    list(registers = as.integer(words_of(lines[1L])[2L]), enabled = PASS_ORDER[PASS_ORDER %in% enabled], maximum_rounds = as.integer(words_of(lines[3L])[2L]))
}
read_runs <- function() {
    lines <- readLines("input/input.txt", warn = FALSE)
    lapply(lines[seq_len(as.integer(lines[1L])) + 1L], function(line) {
        words <- words_of(line)
        lapply(words[seq_len(as.integer(words[1L])) + 1L], gmp::as.bigz)
    })
}
reachable_numbers <- function(graph) which(graph$block_of %in% graph$reachable)
reaching_numbers <- function(flow, number, variable) {
    definitions <- lapply(flow$reaching_before[[number]], key_pair)
    as.integer(vapply(Filter(function(definition) definition[1L] == variable, definitions), function(definition) definition[2L], character(1L)))
}
constant_value <- function(graph, definitions) {
    if (!length(definitions) || 0L %in% definitions) return(NULL)
    value <- NULL
    for (number in definitions) {
        entry <- graph$instructions[[number]]
        if (entry$kind != "copy" || !is_constant(entry$a)) return(NULL)
        if (!is.null(value) && value != entry$a) return(NULL)
        value <- entry$a
    }
    value
}
constant_propagation <- function(function_node, graph, flow) {
    replacements <- vector("list", length(graph$instructions))
    records <- character()
    for (number in reachable_numbers(graph)) {
        original <- graph$instructions[[number]]
        entry <- original
        for (field in operand_fields(original)) {
            variable <- original[[field]]
            if (!is.character(variable)) next
            value <- constant_value(graph, reaching_numbers(flow, number, variable))
            if (!is.null(value)) {
                entry <- if (field == "a") replace_instruction(entry, a = value) else replace_instruction(entry, b = value)
                records <- c(records, paste0("#", number, ": ", variable, " -> ", operand_text(value)))
            }
        }
        folded <- fold_instruction(entry)
        if (is.null(folded$entry)) {
            records <- c(records, paste0("#", number, ": delete ", instruction_string(entry)))
            replacements[[number]] <- list()
        } else {
            if (folded$changed) records <- c(records, paste0("#", number, ": fold ", instruction_string(folded$entry)))
            replacements[[number]] <- list(folded$entry)
        }
    }
    rewrite_code(function_node, replacements)
    list(count = length(records), records = records)
}
copy_propagation <- function(function_node, graph, flow) {
    replacements <- vector("list", length(graph$instructions))
    records <- character()
    for (number in reachable_numbers(graph)) {
        original <- graph$instructions[[number]]
        entry <- original
        available <- new_table()
        for (pair in flow$copy_before[[number]]) {
            parts <- key_pair(pair)
            available[[parts[1L]]] <- parts[2L]
        }
        for (field in operand_fields(original)) {
            variable <- original[[field]]
            if (is.character(variable) && exists(variable, available, inherits = FALSE)) {
                replacement <- available[[variable]]
                entry <- if (field == "a") replace_instruction(entry, a = replacement) else replace_instruction(entry, b = replacement)
                records <- c(records, paste0("#", number, ": ", variable, " -> ", replacement))
            }
        }
        replacements[[number]] <- list(entry)
    }
    rewrite_code(function_node, replacements)
    list(count = length(records), records = records)
}
expression_sources <- function(graph, value, candidate) {
    block_number <- graph$block_of[candidate]
    for (number in rev(graph$blocks[[block_number]]$instructions)) {
        if (number < candidate && identical(expression_key(graph$instructions[[number]]), value)) return(number)
    }
    sources <- examined <- integer()
    pending <- graph$reachable_predecessors[[block_number]]
    while (length(pending)) {
        number <- tail(pending, 1L)
        pending <- head(pending, -1L)
        if (number %in% examined) next
        examined <- c(examined, number)
        found <- FALSE
        for (instruction_number in rev(graph$blocks[[number]]$instructions)) {
            if (identical(expression_key(graph$instructions[[instruction_number]]), value)) {
                sources <- union(sources, instruction_number)
                found <- TRUE
                break
            }
        }
        if (!found) pending <- c(pending, graph$reachable_predecessors[[number]])
    }
    sources
}
common_subexpressions <- function(function_node, graph, flow) {
    candidates <- new_table()
    group_order <- character()
    for (number in reachable_numbers(graph)) {
        value <- expression_key(graph$instructions[[number]])
        if (!is.null(value) && value %in% flow$expression_before[[number]]) {
            if (!exists(value, candidates, inherits = FALSE)) group_order <- c(group_order, value)
            candidates[[value]] <- c(candidates[[value]], number)
        }
    }
    replacements <- vector("list", length(graph$instructions))
    records <- character()
    changes <- 0L
    for (value in group_order) {
        numbers <- candidates[[value]]
        sources <- integer()
        for (number in numbers) sources <- union(sources, expression_sources(graph, value, number))
        sources <- sort(setdiff(sources, numbers))
        edits <- cse_replacements(function_node, graph, sources, numbers)
        for (number in seq_along(edits$replacements)) if (!is.null(edits$replacements[[number]])) replacements[[number]] <- edits$replacements[[number]]
        records <- c(records, paste0(value, ": ", edits$temporary, " sources=", instruction_list(sources), " replaced=", instruction_list(numbers)))
        changes <- changes + length(numbers)
    }
    rewrite_code(function_node, replacements)
    list(count = changes, records = records)
}
dead_code <- function(function_node, graph, flow) {
    replacements <- vector("list", length(graph$instructions))
    records <- list()
    for (block_number in graph$reachable) {
        state <- flow$live_out[[block_number]]
        for (number in rev(graph$blocks[[block_number]]$instructions)) {
            entry <- graph$instructions[[number]]
            destination <- entry$destination
            self_copy <- entry$kind == "copy" && is.character(entry$a) && destination == entry$a
            dead_assignment <- entry$kind %in% c("copy", "bin", "load") && !destination %in% state
            if (self_copy || dead_assignment) {
                replacements[[number]] <- list()
                records[[length(records) + 1L]] <- list(number = number, text = paste0("#", number, ": delete ", instruction_string(entry)))
                next
            }
            if (entry$kind == "call" && !is.null(destination) && !destination %in% state) {
                records[[length(records) + 1L]] <- list(number = number, text = paste0("#", number, ": unused result ", instruction_string(entry)))
                entry <- replace_instruction(entry, destination = NULL)
                replacements[[number]] <- list(entry)
            }
            state <- live_transfer(entry, state)
        }
    }
    rewrite_code(function_node, replacements)
    order <- order(vapply(records, function(record) record$number, integer(1L)))
    ordered <- vapply(records[order], function(record) record$text, character(1L))
    list(count = length(ordered), records = ordered)
}
inside_definitions <- function(graph, loop, definitions) {
    definitions <- definitions[definitions != 0L]
    definitions[graph$block_of[definitions] %in% loop$blocks]
}
invariant_operand <- function(graph, flow, loop, number, variable, marked) {
    definitions <- reaching_numbers(flow, number, variable)
    inside <- inside_definitions(graph, loop, definitions)
    !length(inside) || (length(definitions) == 1L && all(inside %in% marked))
}
marked_invariants <- function(graph, flow, loop, numbers) {
    stores <- character()
    calls <- FALSE
    for (number in numbers) {
        entry <- graph$instructions[[number]]
        if (entry$kind == "store") stores <- union(stores, entry$name)
        if (entry$kind == "call") calls <- TRUE
    }
    marked <- order <- integer()
    repeat {
        changed <- FALSE
        for (number in numbers) {
            entry <- graph$instructions[[number]]
            if (number %in% marked || !entry$kind %in% c("copy", "bin", "load")) next
            if (entry$kind == "load" && (calls || entry$name %in% stores)) next
            if (all(vapply(used_variables(entry), function(variable) invariant_operand(graph, flow, loop, number, variable, marked), logical(1L)))) {
                marked <- c(marked, number)
                order <- c(order, number)
                changed <- TRUE
            }
        }
        if (!changed) return(order)
    }
}
movable_invariants <- function(graph, flow, loop, numbers, marked_order) {
    definitions <- new_table()
    for (number in numbers) {
        destination <- graph$instructions[[number]]$destination
        if (!is.null(destination)) definitions[[destination]] <- if (exists(destination, definitions, inherits = FALSE)) definitions[[destination]] + 1L else 1L
    }
    moved <- order <- integer()
    for (number in marked_order) {
        entry <- graph$instructions[[number]]
        destination <- entry$destination
        if (definitions[[destination]] != 1L || destination %in% flow$live_in[[loop$header]]) next
        block_number <- graph$block_of[number]
        dominates_exits <- all(vapply(loop$exits, function(exit_block) block_number %in% graph$dominators[[exit_block]], logical(1L)))
        dangerous <- entry$kind == "load" || (entry$kind == "bin" && entry$operation %in% c("/", "%") && (is.character(entry$b) || entry$b == 0L))
        dead_outside <- all(vapply(loop$outside, function(successor) !destination %in% flow$live_in[[successor]], logical(1L)))
        if (!dominates_exits && (dangerous || !dead_outside)) next
        ready <- all(vapply(used_variables(entry), function(variable) {
            all(inside_definitions(graph, loop, reaching_numbers(flow, number, variable)) %in% moved)
        }, logical(1L)))
        if (ready) {
            moved <- c(moved, number)
            order <- c(order, number)
        }
    }
    order
}
loop_invariant_motion <- function(function_node, graph, flow) {
    loops <- graph$loops
    order <- order(vapply(loops, function(loop) length(loop$blocks), integer(1L)), vapply(loops, function(loop) loop$header, integer(1L)))
    for (loop in loops[order]) {
        numbers <- sort(unlist(lapply(loop$blocks, function(block) graph$blocks[[block]]$instructions), use.names = FALSE))
        marked <- marked_invariants(graph, flow, loop, numbers)
        moves <- movable_invariants(graph, flow, loop, numbers, marked)
        if (length(moves)) {
            destination <- hoist(function_node, graph, loop, moves)
            return(list(count = length(moves), records = paste0("B", loop$header, ": hoist ", instruction_list(moves), " to ", destination)))
        }
    }
    list(count = 0L, records = character())
}
unreachable_code <- function(function_node, graph, flow) {
    removed <- remove_unreachable(function_node, graph)
    records <- c(vapply(removed$blocks, function(number) paste0("remove block B", number), character(1L)),
        vapply(removed$jumps, function(number) paste0("remove jump #", number), character(1L)),
        vapply(removed$labels, function(label) paste("remove label", label), character(1L)))
    list(count = length(records), records = records)
}
PASSES <- list(constprop = constant_propagation, copyprop = copy_propagation, cse = common_subexpressions,
    dce = dead_code, licm = loop_invariant_motion, unreachable = unreachable_code)
optimize_function <- function(function_node, enabled, maximum_rounds, totals) {
    original_count <- length(instructions(function_node))
    lines <- paste0("== ", function_node$name, " ==")
    for (round_number in seq_len(maximum_rounds)) {
        counts <- integer()
        records <- character()
        for (name in enabled) {
            graph <- new_cfg(function_node)
            flow <- new_dataflow(graph)
            result <- PASSES[[name]](function_node, graph, flow)
            counts <- c(counts, result$count)
            totals[[name]] <- totals[[name]] + result$count
            records <- c(records, vapply(result$records, function(record) paste(" ", name, record), character(1L)))
        }
        lines <- c(lines, paste0("round ", round_number, ": ", paste0(enabled, "=", counts, collapse = " ")), records)
        if (all(counts == 0L)) break
    }
    c(lines, paste0("result: rounds=", round_number, " instructions=", original_count, "->", length(instructions(function_node))))
}
reachable_names <- function(callees, starts) {
    reached <- character()
    pending <- starts
    while (length(pending)) {
        name <- tail(pending, 1L)
        pending <- head(pending, -1L)
        if (!name %in% reached) {
            reached <- c(reached, name)
            pending <- c(pending, callees[[name]])
        }
    }
    reached
}
call_graph <- function(program) {
    names <- vapply(program$functions, function(function_node) function_node$name, character(1L))
    callees <- setNames(vector("list", length(names)), names)
    for (function_node in program$functions) {
        called <- vapply(Filter(function(entry) entry$kind == "call", instructions(function_node)), function(entry) entry$name, character(1L))
        callees[[function_node$name]] <- names[names %in% called]
    }
    recursive <- names[vapply(names, function(name) name %in% reachable_names(callees, callees[[name]]), logical(1L))]
    list(callees = callees, reachable = reachable_names(callees, "main"), recursive = recursive)
}
call_graph_lines <- function(program, heading) {
    graph <- call_graph(program)
    lines <- paste0("== call graph (", heading, ") ==")
    names <- vapply(program$functions, function(function_node) function_node$name, character(1L))
    for (name in names) lines <- c(lines, paste0(name, " -> ", comma_list(graph$callees[[name]]), if (name %in% graph$recursive) " (recursive)" else ""))
    list(lines = c(lines, paste0("unreachable functions: ", comma_list(names[!names %in% graph$reachable]))), reachable = graph$reachable)
}
definition_list <- function(definitions) {
    if (!length(definitions)) return("-")
    parts <- lapply(definitions, key_pair)
    order <- order(as.integer(vapply(parts, function(pair) pair[2L], character(1L))), vapply(parts, function(pair) pair[1L], character(1L)), method = "radix")
    comma_list(definitions[order])
}
function_analysis <- function(function_node, heading) {
    graph <- new_cfg(function_node)
    flow <- new_dataflow(graph)
    lines <- c(paste0("== ", function_node$name, " (", heading, ") =="), "code:")
    number <- 0L
    for (line in function_node$code) {
        if (is.character(line)) {
            lines <- c(lines, paste0(line, ":"))
            next
        }
        number <- number + 1L
        text <- paste0("  #", number, " ", instruction_string(line))
        if (graph$block_of[number] %in% graph$reachable) {
            variables <- unique(used_variables(line))
            if (length(variables)) {
                chains <- vapply(variables, function(variable) paste0(variable, ":", comma_list(sort(reaching_numbers(flow, number, variable)))), character(1L))
                text <- paste0(text, " | ", paste(chains, collapse = " "))
            }
        }
        lines <- c(lines, text)
    }
    lines <- c(lines, paste("blocks:", length(graph$blocks)))
    for (block in graph$blocks) lines <- c(lines, paste0("B", block$number, " ", block$instructions[1L], "-", tail(block$instructions, 1L),
        " labels=", comma_list(block$labels), " preds=", block_list(block$predecessors), " succs=", block_list(block$successors)))
    lines <- c(lines, paste0("unreachable: ", block_list(setdiff(seq_along(graph$blocks), graph$reachable))),
        paste0("order: ", block_list(graph$reverse_postorder)), "dominators:")
    for (number in graph$reachable) {
        parent <- graph$immediate[number]
        lines <- c(lines, paste0("B", number, " idom=", if (parent == 0L) "-" else paste0("B", parent), " dom=", block_list(sort(graph$dominators[[number]]))))
    }
    lines <- c(lines, "dominator tree:")
    stack <- list(c(1L, 0L))
    while (length(stack)) {
        frame <- stack[[length(stack)]]
        stack[[length(stack)]] <- NULL
        lines <- c(lines, paste0(strrep("  ", frame[2L]), "B", frame[1L]))
        for (child in rev(which(graph$immediate == frame[1L]))) stack[[length(stack) + 1L]] <- c(child, frame[2L] + 1L)
    }
    lines <- c(lines, paste("loops:", length(graph$loops)))
    for (loop in graph$loops) lines <- c(lines, paste0("header=B", loop$header, " latches=", block_list(loop$latches),
        " depth=", loop$depth, " blocks=", block_list(loop$blocks), " exits=", block_list(sort(loop$exits))))
    analyses <- list(list(title = "reaching definitions", key = "reaching", incoming = flow$reaching_in, outgoing = flow$reaching_out, render = definition_list),
        list(title = "liveness", key = "liveness", incoming = flow$live_in, outgoing = flow$live_out, render = function(state) comma_list(sort(state, method = "radix"))),
        list(title = "available expressions", key = "expressions", incoming = flow$expression_in, outgoing = flow$expression_out, render = function(state) comma_list(sort(state, method = "radix"))))
    for (analysis in analyses) {
        lines <- c(lines, paste0(analysis$title, ": iterations=", flow$iterations[[analysis$key]]))
        for (number in graph$reachable) lines <- c(lines, paste0("B", number, " in=", analysis$render(analysis$incoming[[number]]), " out=", analysis$render(analysis$outgoing[[number]])))
    }
    lines
}
rewrite_registers <- function(function_node, colors) {
    assigned <- colors[colors >= 0L]
    names <- if (length(assigned)) setNames(paste0("R", assigned), names(assigned)) else setNames(character(), character())
    renamed <- function(value) if (is.character(value) && value %in% names(names)) names[[value]] else value
    code <- list()
    moves <- 0L
    for (line in function_node$code) {
        if (is.character(line)) {
            code[[length(code) + 1L]] <- line
            next
        }
        entry <- replace_instruction(line, destination = renamed(line$destination), a = renamed(line$a), b = renamed(line$b))
        if (entry$kind == "copy" && is.character(entry$a) && entry$destination == entry$a) moves <- moves + 1L else code[[length(code) + 1L]] <- entry
    }
    parameters <- vapply(function_node$parameters, renamed, character(1L))
    list(function_node = new_function(function_node$name, parameters, code), moves = moves)
}
allocation_report <- function(function_node, registers) {
    graph <- new_cfg(function_node)
    flow <- new_dataflow(graph)
    allocation <- new_allocation(function_node, graph, flow, registers)
    rewritten <- rewrite_registers(function_node, allocation$colors)
    nodes <- allocation$nodes
    edges <- sum(vapply(nodes, function(node) length(allocation$neighbors[[node]]), integer(1L))) %/% 2L
    lines <- c(paste0("== ", function_node$name, " =="), paste0("nodes=", length(nodes), " edges=", edges, " registers=", registers))
    for (node in nodes) lines <- c(lines, paste0(node, " degree=", length(allocation$neighbors[[node]]),
        " cost=", as.character(allocation$costs[[node]]), " neighbors=", comma_list(sort(allocation$neighbors[[node]], method = "radix"))))
    potential <- vapply(allocation$potential, function(pair) paste0(pair$node, "(", as.character(allocation$costs[[pair$node]]), "/", pair$degree, ")"), character(1L))
    lines <- c(lines, paste0("simplify: ", comma_list(allocation$order)), paste0("potential spills: ", comma_list(potential)))
    for (node in nodes) lines <- c(lines, paste(node, "->", if (allocation$colors[[node]] < 0L) "spill" else paste0("R", allocation$colors[[node]])))
    pressure <- max(c(0L, lengths(flow$live_before), lengths(flow$live_after)))
    used <- length(unique(allocation$colors[allocation$colors >= 0L]))
    spills <- allocation$spills
    spill_uses <- sum(vapply(instructions(function_node), function(entry) sum(used_variables(entry) %in% spills), integer(1L)))
    spill_defs <- sum(vapply(instructions(function_node), function(entry) !is.null(entry$destination) && entry$destination %in% spills, logical(1L)))
    spill_defs <- spill_defs + sum(function_node$parameters %in% spills)
    lines <- c(lines, paste0("summary: pressure=", pressure, " used=", used, " spilled=", length(spills), " moves=", rewritten$moves,
        " spill_uses=", spill_uses, " spill_defs=", spill_defs), function_lines(rewritten$function_node))
    list(function_node = rewritten$function_node, lines = lines)
}
new_interpreter <- function(program, inputs) {
    functions <- new_table()
    arrays <- new_table()
    for (function_node in program$functions) {
        labels <- new_table()
        code <- list()
        for (line in function_node$code) {
            if (is.character(line)) labels[[line]] <- length(code) + 1L else code[[length(code) + 1L]] <- line
        }
        functions[[function_node$name]] <- list(parameters = function_node$parameters, instructions = code, labels = labels)
    }
    for (array in program$arrays) arrays[[array$name]] <- rep(list(gmp::as.bigz(0L)), array$size)
    names <- vapply(program$functions, function(function_node) function_node$name, character(1L))
    record(functions = functions, arrays = arrays, inputs = inputs, input_position = 1L, output = list(),
        steps = setNames(integer(length(names)), names), calls = setNames(integer(length(names)), names), kinds = setNames(integer(length(KINDS)), KINDS))
}
value_of <- function(operand, variables) if (is.character(operand)) variables[[operand]] else operand
call_tac <- function(interpreter, name, arguments) {
    function_node <- interpreter$functions[[name]]
    variables <- new_table()
    for (index in seq_along(function_node$parameters)) variables[[function_node$parameters[index]]] <- arguments[[index]]
    pushed <- list()
    position <- 1L
    interpreter$calls[[name]] <- interpreter$calls[[name]] + 1L
    repeat {
        entry <- function_node$instructions[[position]]
        position <- position + 1L
        interpreter$steps[[name]] <- interpreter$steps[[name]] + 1L
        interpreter$kinds[[entry$kind]] <- interpreter$kinds[[entry$kind]] + 1L
        kind <- entry$kind
        if (kind == "copy") {
            variables[[entry$destination]] <- value_of(entry$a, variables)
        } else if (kind == "bin") {
            variables[[entry$destination]] <- calculate(entry$operation, value_of(entry$a, variables), value_of(entry$b, variables))
        } else if (kind == "load") {
            index <- as.integer(value_of(entry$a, variables)) + 1L
            variables[[entry$destination]] <- interpreter$arrays[[entry$name]][[index]]
        } else if (kind == "store") {
            index <- as.integer(value_of(entry$a, variables)) + 1L
            interpreter$arrays[[entry$name]][[index]] <- value_of(entry$b, variables)
        } else if (kind == "goto") {
            position <- function_node$labels[[entry$name]]
        } else if (kind == "if") {
            if (calculate(entry$operation, value_of(entry$a, variables), value_of(entry$b, variables)) != 0L) position <- function_node$labels[[entry$name]]
        } else if (kind == "param") {
            pushed[[length(pushed) + 1L]] <- value_of(entry$a, variables)
        } else if (kind == "call") {
            arguments <- if (entry$count == 0L) list() else tail(pushed, entry$count)
            if (entry$count != 0L) pushed <- head(pushed, length(pushed) - entry$count)
            result <- call_tac(interpreter, entry$name, arguments)
            if (!is.null(entry$destination)) variables[[entry$destination]] <- result
        } else if (kind == "return") {
            return(value_of(entry$a, variables))
        } else if (kind == "read") {
            variables[[entry$destination]] <- interpreter$inputs[[interpreter$input_position]]
            interpreter$input_position <- interpreter$input_position + 1L
        } else interpreter$output[[length(interpreter$output) + 1L]] <- value_of(entry$a, variables)
    }
}
static_kinds <- function(program) {
    counts <- setNames(integer(length(KINDS)), KINDS)
    for (function_node in program$functions) for (entry in instructions(function_node)) counts[[entry$kind]] <- counts[[entry$kind]] + 1L
    counts
}
equal_outputs <- function(first, second) {
    length(first) == length(second) && all(vapply(seq_along(first), function(index) first[[index]] == second[[index]], logical(1L)))
}
comparison_report <- function(original, optimized, allocated, runs) {
    programs <- list(original, optimized, allocated)
    names <- vapply(original$functions, function(function_node) function_node$name, character(1L))
    profiles <- setNames(lapply(VERSIONS, function(version) setNames(integer(length(names)), names)), VERSIONS)
    dynamic <- setNames(lapply(VERSIONS, function(version) setNames(integer(length(KINDS)), KINDS)), VERSIONS)
    total_steps <- setNames(integer(length(VERSIONS)), VERSIONS)
    original_calls <- setNames(integer(length(names)), names)
    lines <- character()
    same <- 0L
    for (run_number in seq_along(runs)) {
        inputs <- runs[[run_number]]
        lines <- c(lines, paste0("run ", run_number, ": inputs=", length(inputs)))
        outputs <- list()
        for (index in seq_along(VERSIONS)) {
            version <- VERSIONS[index]
            interpreter <- new_interpreter(programs[[index]], inputs)
            call_tac(interpreter, "main", list())
            steps <- sum(interpreter$steps)
            calls <- sum(interpreter$calls)
            output <- vapply(interpreter$output, as.character, character(1L))
            lines <- c(lines, paste0("  ", version, ": steps=", steps, " calls=", calls, " output=", comma_list(output)))
            for (name in names(interpreter$steps)) profiles[[version]][[name]] <- profiles[[version]][[name]] + interpreter$steps[[name]]
            dynamic[[version]] <- dynamic[[version]] + interpreter$kinds
            total_steps[[version]] <- total_steps[[version]] + steps
            if (version == "original") for (name in names(interpreter$calls)) original_calls[[name]] <- original_calls[[name]] + interpreter$calls[[name]]
            outputs[[index]] <- interpreter$output
        }
        equal <- equal_outputs(outputs[[1L]], outputs[[2L]]) && equal_outputs(outputs[[2L]], outputs[[3L]])
        same <- same + as.integer(equal)
        lines <- c(lines, paste0("  result: ", if (equal) "same" else "different"))
    }
    lines <- c(lines, "== profile ==")
    for (name in names) lines <- c(lines, paste0(name, ": calls=", original_calls[[name]], " original=", profiles$original[[name]],
        " optimized=", profiles$optimized[[name]], " allocated=", profiles$allocated[[name]]))
    original_kinds <- static_kinds(original)
    optimized_kinds <- static_kinds(optimized)
    lines <- c(lines, "== summary ==", paste0("runs=", length(runs), " same=", same, " different=", length(runs) - same),
        paste0("instructions: original=", sum(original_kinds), " optimized=", sum(optimized_kinds)),
        paste0("kinds: ", paste0(KINDS, "=", original_kinds, "->", optimized_kinds, collapse = " ")),
        paste0("steps: ", paste0(VERSIONS, "=", total_steps, collapse = " ")))
    for (version in VERSIONS) lines <- c(lines, paste0("dynamic ", version, ": ", paste0(KINDS, "=", dynamic[[version]], collapse = " ")))
    lines
}
main <- function() {
    options(expressions = 100000L)
    settings <- read_settings()
    runs <- read_runs()
    original <- read_program("input/program.tac")
    original_graph <- call_graph_lines(original, "original")
    analysis <- original_graph$lines
    for (function_node in original$functions) analysis <- c(analysis, function_analysis(function_node, "original"))
    working <- list(arrays = original$arrays, functions = lapply(original$functions, function(function_node) new_function(function_node$name, function_node$parameters, function_node$code)))
    pass_lines <- character()
    totals <- new_table()
    for (name in settings$enabled) totals[[name]] <- 0L
    for (function_node in working$functions) pass_lines <- c(pass_lines, optimize_function(function_node, settings$enabled, settings$maximum_rounds, totals))
    graph <- call_graph_lines(working, "optimized")
    analysis <- c(analysis, graph$lines)
    removed <- vapply(Filter(function(function_node) "unreachable" %in% settings$enabled && !function_node$name %in% graph$reachable, working$functions), function(function_node) function_node$name, character(1L))
    optimized <- list(arrays = working$arrays, functions = Filter(function(function_node) !function_node$name %in% removed, working$functions))
    pass_lines <- c(pass_lines, "== program ==", paste0("removed functions: ", comma_list(removed)), "== total ==",
        paste0(vapply(settings$enabled, function(name) paste0(name, "=", totals[[name]]), character(1L)), collapse = " "))
    allocated_functions <- list()
    allocation_lines <- character()
    for (function_node in optimized$functions) {
        analysis <- c(analysis, function_analysis(function_node, "optimized"))
        allocation <- allocation_report(function_node, settings$registers)
        allocated_functions[[length(allocated_functions) + 1L]] <- allocation$function_node
        allocation_lines <- c(allocation_lines, allocation$lines)
    }
    allocated <- list(arrays = optimized$arrays, functions = allocated_functions)
    reports <- list("optimized.tac" = program_lines(optimized), "analysis.txt" = analysis, "passes.txt" = pass_lines,
        "regalloc.txt" = allocation_lines, "comparison.txt" = comparison_report(original, optimized, allocated, runs))
    for (filename in names(reports)) writeLines(reports[[filename]], file.path("output", filename), useBytes = TRUE)
}
main()
