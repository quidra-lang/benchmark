subtype <- function(parents, actual, expected) {
    while (!is.null(actual)) {
        if (actual == expected) return(TRUE)
        actual <- parents[[actual]]
    }
    FALSE
}
predicate_classes <- function(domain) {
    fluent <- unique(unlist(lapply(domain$actions, function(a) vapply(a$effects, function(l) l$atom[1], "")), use.names=FALSE))
    list(fluent=fluent, static=setdiff(domain$predicate_order, fluent))
}
substitute <- function(atom, assignment) c(atom[1], unname(assignment[atom[-1]]))
ground <- function(domain, problem) {
    objects_by_type <- setNames(lapply(domain$type_order, function(kind) {
        problem$object_order[vapply(problem$object_order, function(name) subtype(domain$parents, problem$objects[[name]], kind), FALSE)]
    }), domain$type_order)
    atom_store <- new.env(hash=TRUE, parent=emptyenv())
    key_atom <- function(atom) {
        key <- notation(atom)
        atom_store[[key]] <- atom
        key
    }
    initial_atoms <- vapply(problem$initial, key_atom, "")
    candidates <- list()
    statistics <- list()
    for (schema in domain$actions) {
        choices <- lapply(schema$parameters, function(p) objects_by_type[[p[2]]])
        counts <- c(prod(lengths(choices)), 0L, 0L)
        assign_objects <- function(arguments, index) {
            if (index <= length(choices)) {
                for (name in choices[[index]]) assign_objects(c(arguments, name), index+1L)
                return(invisible(NULL))
            }
            binding <- setNames(arguments, vapply(schema$parameters, function(p) p[1], ""))
            positive <- negative <- character()
            for (literal in schema$condition) {
                bound <- substitute(literal$atom, binding)
                if (bound[1] == "=") {
                    truth <- bound[2] == bound[3]
                } else if (bound[1] %in% domain$static) {
                    truth <- key_atom(bound) %in% initial_atoms
                } else {
                    key <- key_atom(bound)
                    if (literal$sign) positive <- union(positive, key) else negative <- union(negative, key)
                    next
                }
                if (truth != literal$sign) return(invisible(NULL))
            }
            adds <- deletes <- character()
            for (literal in schema$effects) {
                key <- key_atom(substitute(literal$atom, binding))
                if (literal$sign) adds <- union(adds, key) else deletes <- union(deletes, key)
            }
            candidates[[length(candidates)+1L]] <<- list(source=schema, arguments=arguments, cost=schema$cost,
                pre=positive, neg=negative, add=adds, delete=setdiff(deletes, adds))
            counts[2] <<- counts[2]+1L
        }
        assign_objects(character(), 1L)
        statistics[[schema$name]] <- counts
    }
    reachable <- initial_atoms[vapply(problem$initial, function(a) a[1] %in% domain$fluent, FALSE)]
    accepted <- rep(FALSE, length(candidates))
    repeat {
        changed <- FALSE
        for (i in seq_along(candidates)) {
            candidate <- candidates[[i]]
            if (!accepted[i] && all(candidate$pre %in% reachable)) {
                accepted[i] <- TRUE
                reachable <- union(reachable, candidate$add)
                name <- candidate$source$name
                statistics[[name]][3] <- statistics[[name]][3]+1L
                changed <- TRUE
            }
        }
        if (!changed) break
    }
    fact_keys <- unique(reachable)
    facts <- lapply(fact_keys, function(key) atom_store[[key]])
    sort_keys <- vapply(facts, function(atom) paste0(sprintf("%02d", match(atom[1], domain$predicate_order)),
        paste(sprintf("%02d", match(atom[-1], problem$object_order)), collapse="")), "")
    order <- order(sort_keys, method="radix")
    facts <- facts[order]
    fact_keys <- fact_keys[order]
    fact_numbers <- setNames(seq_along(fact_keys)-1L, fact_keys)
    actions <- list()
    for (i in which(accepted)) {
        candidate <- candidates[[i]]
        mapped <- lapply(candidate[c("pre", "neg", "add", "delete")], function(values) sort(unname(fact_numbers[intersect(values, fact_keys)])))
        actions[[length(actions)+1L]] <- c(list(number=length(actions), source=candidate$source,
            arguments=candidate$arguments, cost=candidate$cost), mapped)
    }
    initial <- sort(unname(fact_numbers[initial_atoms[vapply(problem$initial, function(a) a[1] %in% domain$fluent, FALSE)]]))
    goal <- integer()
    unreachable <- list()
    for (atom in problem$goals) {
        key <- notation(atom)
        if (key %in% fact_keys) goal <- union(goal, fact_numbers[[key]]) else {
            if (!atom[1] %in% domain$static || !key %in% initial_atoms) unreachable[[length(unreachable)+1L]] <- atom
        }
    }
    action_numbers <- setNames(vapply(actions, function(a) a$number, 0L), vapply(actions, action_text, ""))
    list(name=problem$name, source=problem, objects_by_type=objects_by_type, statistics=statistics,
        candidate_count=length(candidates), facts=facts, actions=actions, initial=initial, goal=sort(goal),
        unreachable=unreachable, static_count=sum(vapply(problem$initial, function(a) a[1] %in% domain$static, FALSE)),
        action_numbers=action_numbers)
}
