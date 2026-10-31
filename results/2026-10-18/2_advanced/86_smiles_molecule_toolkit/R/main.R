source("molecule.R")
source("smiles_parser.R")
source("rings_aromatic.R")
source("canonical.R")
source("search.R")
QUERY_COUNTS <- list(MATCH=c(1L,1L), CONTAINS=c(2L,2L), MATRIX=c(2L,12L),
    NEAREST=c(2L,2L), WITHIN=c(2L,2L), COMPARE=c(2L,2L), CLUSTER=c(1L,1L))
SYSTEM_KINDS <- c("isolated", "fused", "spiro", "bridged")
line <- function(...) {
    parts <- lapply(list(...), function(x) if (is.numeric(x)) sprintf("%.0f", x) else as.character(x))
    paste(unlist(parts), collapse=" ")
}
kv <- function(key, value) paste0(key, "=", if (is.numeric(value)) sprintf("%.0f", value) else value)
valid_name <- function(value) grepl("^[A-Za-z0-9_-]{1,32}$", value)
valid_number <- function(value, low, high) {
    grepl("^(0|[1-9][0-9]*)$", value) && nchar(value) <= nchar(as.character(high)) &&
        as.numeric(value) >= low && as.numeric(value) <= high
}
data_lines <- function(name) {
    lines <- readLines(file.path("input", name), warn=FALSE)
    indices <- which(nzchar(lines) & !startsWith(lines, "#"))
    lapply(indices, function(i) list(number=i, text=lines[i]))
}
threshold <- function(value) {
    parts <- strsplit(value, "/", fixed=TRUE)[[1]]
    if (length(parts) != 2L || endsWith(value, "/") || !valid_number(parts[1], 0, 99) ||
        !valid_number(parts[2], 1, 99)) return(NULL)
    values <- as.integer(parts)
    if (values[1] <= values[2]) values else NULL
}
gcd_integer <- function(a, b) {
    while (b != 0L) {
        remainder <- a %% b
        a <- b
        b <- remainder
    }
    a
}
fraction_text <- function(value) {
    divisor <- gcd_integer(value[1], value[2])
    paste0(value[1] %/% divisor, "/", value[2] %/% divisor)
}
fraction_compare <- function(a, b) sign(a[1]*b[2]-b[1]*a[2])
member_names <- function(molecules) paste(vapply(molecules, function(m) m$name, ""), collapse=",")
cause <- function(causes, reason) {
    previous <- causes[[reason]]
    causes[[reason]] <- if (is.null(previous)) 1L else previous+1L
}
analyze <- function(m) {
    find_rings(m)
    for (bond in ordered_bonds(m)) {
        a <- bond$ends[1]
        b <- bond$ends[2]
        bond$kind <- if (is.null(bond$symbol)) {
            if (bond$ring && m$atoms[[a]]$aromatic && m$atoms[[b]]$aromatic) 4L else 1L
        } else BOND_TYPES[[bond$symbol]]
    }
    kekulize(m, which(vapply(seq_along(m$atoms), function(a) needs_pi(m, a), FALSE)))
    for (a in seq_along(m$atoms)) {
        atom <- m$atoms[[a]]
        total <- bond_total(m, a)
        if (atom$bracket) {
            if (total+atom$hydrogens > max(atom$element$valences)+abs(atom$charge)) {
                analysis_error("bad valence", atom$column)
            }
        } else {
            h <- organic_hydrogens(atom, total)
            if (is.null(h)) analysis_error("bad valence", atom$column)
            atom$hydrogens <- h
        }
    }
}
molecular_properties <- function(m) {
    counts <- table(vapply(m$atoms, function(a) a$element$symbol, ""))
    counts <- setNames(as.integer(counts), names(counts))
    hydrogens <- sum(vapply(m$atoms, function(a) a$hydrogens, 0L))
    if (!"H" %in% names(counts)) counts["H"] <- 0L
    counts["H"] <- counts["H"]+hydrogens
    symbols <- sort(names(counts)[counts > 0L], method="radix")
    if ("C" %in% symbols) {
        symbols <- c("C", if ("H" %in% symbols) "H" else character(), setdiff(symbols, c("C", "H")))
    }
    formula <- paste(vapply(symbols, function(s) paste0(s, if (counts[[s]] == 1L) "" else counts[[s]]), ""), collapse="")
    weight <- sum(vapply(m$atoms, function(a) if (a$mass == 0L) a$element$weight else a$mass*1000L, 0L))
    weight <- weight+hydrogens*m$elements$H$weight
    heavy <- sum(vapply(m$atoms, function(a) a$element$symbol != "H", FALSE))
    heavy_degrees <- vapply(seq_along(m$atoms), function(a) {
        sum(vapply(neighbor_numbers(m, a), function(b) m$atoms[[b]]$element$symbol != "H", FALSE))
    }, 0L)
    triple_ends <- unique(unlist(lapply(Filter(function(b) b$multiplicity == 3L, ordered_bonds(m)),
        function(b) b$ends), use.names=FALSE))
    rotatable <- 0L
    for (bond in ordered_bonds(m)) {
        a <- bond$ends[1]
        b <- bond$ends[2]
        if (bond$multiplicity == 1L && !bond$ring && heavy_degrees[a] >= 2L && heavy_degrees[b] >= 2L &&
            !a %in% triple_ends && !b %in% triple_ends) rotatable <- rotatable+1L
    }
    donors <- acceptors <- 0L
    for (a in seq_along(m$atoms)) {
        atom <- m$atoms[[a]]
        if (!atom$element$symbol %in% c("N", "O")) next
        acceptors <- acceptors+1L
        attached <- atom$hydrogens+sum(vapply(neighbor_numbers(m, a),
            function(b) m$atoms[[b]]$element$symbol == "H", FALSE))
        donors <- donors+as.integer(attached >= 1L)
    }
    violations <- as.integer(weight > 500000L)+as.integer(donors > 5L)+as.integer(acceptors > 10L)
    list(formula=formula, weight=weight, heavy=heavy, rotatable=rotatable, donors=donors, acceptors=acceptors,
        lipinski=if (violations <= 1L) "pass" else "fail", charge=sum(vapply(m$atoms, function(a) a$charge, 0L)))
}
scaffold_molecule <- function(m) {
    if (!length(m$rings)) return(NULL)
    remaining <- seq_along(m$atoms)
    repeat {
        candidates <- sort(setdiff(remaining, m$ring_atoms))
        leaves <- candidates[vapply(candidates, function(a) sum(neighbor_numbers(m, a) %in% remaining) == 1L, FALSE)]
        if (!length(leaves)) break
        remaining <- setdiff(remaining, leaves[1])
    }
    kept <- remaining
    for (a in remaining) for (b in neighbor_numbers(m, a)) {
        if (!b %in% remaining && get_bond(m, a, b)$kind == 2L) kept <- union(kept, b)
    }
    scaffold <- new_molecule(m$elements)
    renumber <- integer(length(m$atoms))
    for (a in sort(kept)) {
        original <- m$atoms[[a]]
        removed <- setdiff(neighbor_numbers(m, a), kept)
        added <- sum(vapply(removed, function(b) get_bond(m, a, b)$multiplicity, 0L))
        atom <- new_atom(original$element, original$aromatic, original$mass, original$charge,
            original$hydrogens+added, original$bracket, original$column)
        renumber[a] <- add_atom(scaffold, atom)
    }
    for (original in ordered_bonds(m)) {
        a <- original$ends[1]
        b <- original$ends[2]
        if (!a %in% kept || !b %in% kept) next
        bond <- add_bond(scaffold, renumber[a], renumber[b], original$symbol)
        bond$kind <- original$kind
        bond$multiplicity <- original$multiplicity
        bond$ring <- original$ring
    }
    scaffold$rings <- lapply(m$rings, function(r) renumber[r])
    scaffold$ring_atoms <- renumber[m$ring_atoms]
    scaffold
}
ring_systems <- function(m) {
    rings <- m$rings
    connections <- rep(list(integer()), length(rings))
    relations <- list()
    for (i in seq_along(rings)) if (i < length(rings)) for (j in seq.int(i+1L, length(rings))) {
        shared <- sort(intersect(rings[[i]], rings[[j]]))
        if (!length(shared)) next
        connections[[i]] <- c(connections[[i]], j)
        connections[[j]] <- c(connections[[j]], i)
        kind <- if (length(shared) == 1L) "spiro" else if (length(shared) == 2L &&
            !is.null(get_bond(m, shared[1], shared[2]))) "fused" else "bridged"
        relations[[length(relations)+1L]] <- list(i=i, j=j, kind=kind)
    }
    systems <- list()
    remaining <- seq_along(rings)
    while (length(remaining)) {
        start <- min(remaining)
        remaining <- setdiff(remaining, start)
        queue <- start
        head <- 1L
        while (head <= length(queue)) {
            i <- queue[head]
            head <- head+1L
            for (j in sort(connections[[i]])) if (j %in% remaining) {
                remaining <- setdiff(remaining, j)
                queue <- c(queue, j)
            }
        }
        kinds <- vapply(Filter(function(r) r$i %in% queue && r$j %in% queue, relations), function(r) r$kind, "")
        kind <- if (length(queue) == 1L) "isolated" else if ("bridged" %in% kinds) "bridged" else if ("fused" %in% kinds) "fused" else "spiro"
        atoms <- unique(unlist(rings[queue], use.names=FALSE))
        systems[[length(systems)+1L]] <- list(rings=sort(queue), atoms=length(atoms), kind=kind)
    }
    systems
}
read_molecules <- function(elements, causes) {
    molecules <- list()
    errors <- reserved <- character()
    lines <- data_lines("molecules.smi")
    for (record in lines) {
        tokens <- strsplit(record$text, " ", fixed=TRUE)[[1]]
        if (endsWith(record$text, " ")) tokens <- c(tokens, "")
        if (length(tokens) != 2L || !nzchar(tokens[1]) || !valid_name(tokens[2])) {
            errors <- c(errors, paste0("line ", record$number, ": bad line"))
            cause(causes, "bad line")
            next
        }
        smiles <- tokens[1]
        name <- tokens[2]
        if (name %in% reserved) {
            errors <- c(errors, line("line", record$number, paste0(name, ": duplicate name")))
            cause(causes, "duplicate name")
            next
        }
        reserved <- c(reserved, name)
        molecule <- tryCatch({
            parsed <- parse_smiles(smiles, elements)
            analyze(parsed)
            parsed
        }, analysis_error=function(error) error)
        if (inherits(molecule, "analysis_error")) {
            errors <- c(errors, line("line", record$number, paste0(name, ":"), molecule$reason, "at column", molecule$column))
            cause(causes, molecule$reason)
            next
        }
        molecule$name <- name
        molecule$order <- length(molecules)+1L
        molecule$properties <- molecular_properties(molecule)
        canonical <- canonicalize(molecule)
        molecule$canonical <- canonical$smiles
        molecule$classes <- canonical$classes
        scaffold <- scaffold_molecule(molecule)
        molecule$scaffold <- if (is.null(scaffold)) NULL else canonicalize(scaffold)$smiles
        molecule$systems <- ring_systems(molecule)
        molecule$aromatic_rings <- vapply(molecule$rings,
            function(r) all(vapply(r, function(a) molecule$atoms[[a]]$aromatic, FALSE)), FALSE)
        fp <- fingerprint(molecule)
        molecule$bits <- fp$bits
        molecule$paths <- fp$paths
        molecules[[length(molecules)+1L]] <- molecule
    }
    list(molecules=molecules, paragraph=c(line("MOLECULES", kv("lines", length(lines)),
        kv("valid", length(molecules)), kv("errors", length(errors))), errors))
}
check_query <- function(kind, args, elements, by_name) {
    range <- QUERY_COUNTS[[kind]]
    if (length(args) < range[1] || length(args) > range[2]) return(list(reason="bad arguments"))
    extra <- NULL
    if (kind == "MATCH") {
        extra <- tryCatch(parse_smiles(args[1], elements, pattern=TRUE), analysis_error=function(error) error)
        if (inherits(extra, "analysis_error")) return(list(reason=line("bad pattern", extra$reason, "at column", extra$column)))
    } else if (kind == "CLUSTER") {
        extra <- threshold(args[1])
        if (is.null(extra)) return(list(reason="bad threshold"))
    } else if (kind %in% c("CONTAINS", "MATRIX", "COMPARE")) {
        for (name in args) if (is.null(by_name[[name]])) return(list(reason=paste("unknown molecule", name)))
        if (anyDuplicated(args)) return(list(reason="repeated molecule"))
    } else {
        if (is.null(by_name[[args[1]]])) return(list(reason=paste("unknown molecule", args[1])))
        if (kind == "NEAREST") {
            if (!valid_number(args[2], 1, 99)) return(list(reason="bad count"))
            extra <- as.integer(args[2])
        } else {
            extra <- threshold(args[2])
            if (is.null(extra)) return(list(reason="bad threshold"))
        }
    }
    list(reason="", extra=extra)
}
read_queries <- function(elements, by_name, causes) {
    queries <- list()
    errors <- reserved <- character()
    lines <- data_lines("queries.txt")
    for (record in lines) {
        tokens <- strsplit(record$text, " ", fixed=TRUE)[[1]]
        kind <- tokens[1]
        id <- if (length(tokens) >= 2L) tokens[2] else ""
        reason <- ""
        extra <- NULL
        if (!kind %in% names(QUERY_COUNTS)) {
            reason <- "unknown query"
        } else if (!valid_name(id)) {
            reason <- "bad id"
        } else if (id %in% reserved) {
            reason <- "duplicate id"
        } else {
            reserved <- c(reserved, id)
            checked <- check_query(kind, tokens[-c(1,2)], elements, by_name)
            reason <- checked$reason
            extra <- checked$extra
        }
        if (!nzchar(reason)) {
            queries[[length(queries)+1L]] <- list(kind=kind, id=id, args=tokens[-c(1,2)], extra=extra)
        } else {
            prefix <- if (reason == "unknown query") paste0("line ", record$number, ":") else if (reason == "bad id") {
                line("line", record$number, paste0(kind, ":"))
            } else line("line", record$number, kind, paste0(id, ":"))
            errors <- c(errors, line(prefix, reason))
            cause(causes, if (startsWith(reason, "bad pattern ")) "bad pattern" else if (startsWith(reason, "unknown molecule ")) "unknown molecule" else reason)
        }
    }
    list(queries=queries, paragraph=c(line("QUERIES", kv("lines", length(lines)),
        kv("valid", length(queries)), kv("errors", length(errors))), errors))
}
properties_lines <- function(molecules) {
    lines <- "name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"
    for (m in molecules) {
        p <- m$properties
        weight <- sprintf("%d.%03d", p$weight %/% 1000L, p$weight %% 1000L)
        lines <- c(lines, paste(c(m$name, p$formula, weight, p$heavy, length(m$rings),
            p$rotatable, p$donors, p$acceptors, p$lipinski), collapse=","))
    }
    lines
}
canonical_paragraphs <- function(molecules) {
    by_canonical <- by_formula <- by_scaffold <- list()
    canonical_keys <- formula_keys <- character()
    acyclic <- 0L
    for (m in molecules) {
        key <- m$canonical
        if (is.null(by_canonical[[key]])) canonical_keys <- c(canonical_keys, key)
        by_canonical[[key]] <- c(by_canonical[[key]], list(m))
        key <- m$properties$formula
        if (is.null(by_formula[[key]])) formula_keys <- c(formula_keys, key)
        by_formula[[key]] <- c(by_formula[[key]], list(m))
        if (is.null(m$scaffold)) acyclic <- acyclic+1L else {
            by_scaffold[[m$scaffold]] <- c(by_scaffold[[m$scaffold]], list(m))
        }
    }
    canonical <- line("CANONICAL", kv("molecules", length(molecules)), kv("unique", length(by_canonical)))
    for (m in molecules) {
        charge <- m$properties$charge
        canonical <- c(canonical, line(m$name, m$canonical, kv("classes", m$classes),
            kv("charge", if (charge > 0L) paste0("+", charge) else as.character(charge))))
    }
    duplicate_keys <- canonical_keys[lengths(by_canonical[canonical_keys]) >= 2L]
    duplicates <- line("DUPLICATES", kv("groups", length(duplicate_keys)),
        kv("molecules", sum(lengths(by_canonical[duplicate_keys]))))
    for (i in seq_along(duplicate_keys)) {
        key <- duplicate_keys[i]
        duplicates <- c(duplicates, line("group", i, key, kv("members", member_names(by_canonical[[key]]))))
    }
    forms <- vapply(by_formula, function(members) length(unique(vapply(members, function(m) m$canonical, ""))), 0L)
    isomer_keys <- formula_keys[forms[formula_keys] >= 2L]
    isomers <- line("ISOMERS", kv("groups", length(isomer_keys)))
    for (i in seq_along(isomer_keys)) {
        key <- isomer_keys[i]
        isomers <- c(isomers, line("isomer", i, key, kv("forms", forms[[key]]), kv("members", member_names(by_formula[[key]]))))
    }
    scaffolds <- line("SCAFFOLDS", kv("distinct", length(by_scaffold)), kv("acyclic", acyclic))
    keys <- names(by_scaffold)[order(-lengths(by_scaffold), names(by_scaffold), method="radix")]
    for (i in seq_along(keys)) {
        key <- keys[i]
        scaffolds <- c(scaffolds, line("scaffold", i, key, kv("count", length(by_scaffold[[key]])), kv("members", member_names(by_scaffold[[key]]))))
    }
    list(canonical, duplicates, isomers, scaffolds)
}
ring_paragraphs <- function(molecules) {
    paragraphs <- list()
    sizes <- integer()
    kinds <- setNames(integer(4L), SYSTEM_KINDS)
    aromatic_total <- ring_total <- 0L
    for (m in molecules) {
        if (!length(m$rings)) next
        aromatic_total <- aromatic_total+sum(m$aromatic_rings)
        ring_total <- ring_total+length(m$rings)
        paragraph <- line("MOLECULE", m$name, kv("atoms", length(m$atoms)), kv("bonds", length(m$bonds)),
            kv("rings", length(m$rings)), kv("aromatic", sum(m$aromatic_rings)), kv("systems", length(m$systems)),
            kv("ring_atoms", length(m$ring_atoms)), kv("ring_bonds", sum(vapply(m$bonds, function(b) b$ring, FALSE))))
        for (i in seq_along(m$rings)) {
            ring <- m$rings[[i]]
            hetero <- sum(vapply(ring, function(a) m$atoms[[a]]$element$symbol != "C", FALSE))
            paragraph <- c(paragraph, line("ring", i, kv("size", length(ring)),
                kv("aromatic", if (m$aromatic_rings[i]) "yes" else "no"), kv("hetero", hetero), kv("atoms", paste(ring, collapse="-"))))
            key <- as.character(length(ring))
            if (!key %in% names(sizes)) sizes[key] <- 0L
            sizes[key] <- sizes[key]+1L
        }
        for (i in seq_along(m$systems)) {
            system <- m$systems[[i]]
            kinds[system$kind] <- kinds[system$kind]+1L
            paragraph <- c(paragraph, line("system", i, kv("kind", system$kind),
                kv("rings", paste(system$rings, collapse=",")), kv("atoms", system$atoms)))
        }
        doubles <- vapply(Filter(function(b) b$kind == 4L && b$multiplicity == 2L, ordered_bonds(m)),
            function(b) paste(b$ends, collapse="="), "")
        paragraph <- c(paragraph, line("kekule", if (length(doubles)) paste(doubles, collapse=" ") else "-"))
        paragraphs[[length(paragraphs)+1L]] <- paragraph
    }
    summary <- line("SUMMARY", kv("molecules", length(molecules)), kv("cyclic", length(paragraphs)),
        kv("rings", ring_total), kv("aromatic", aromatic_total))
    keys <- names(sizes)[order(as.integer(names(sizes)))]
    summary <- c(summary, line("sizes", if (length(keys)) kv(keys, sizes[keys]) else "-"),
        line("systems", kv(SYSTEM_KINDS, kinds[SYSTEM_KINDS])))
    c(paragraphs, list(summary))
}
substructure_paragraphs <- function(queries, molecules, by_name) {
    paragraphs <- list()
    patterns <- hits <- contains <- found <- 0L
    for (query in queries) {
        kind <- query$kind
        id <- query$id
        args <- query$args
        if (kind == "MATCH") {
            patterns <- patterns+1L
            matches <- lapply(molecules, function(m) list(m=m, result=embeddings(query$extra, m)))
            matches <- Filter(function(r) r$result$count > 0L, matches)
            hits <- hits+length(matches)
            total <- sum(vapply(matches, function(r) r$result$count, 0L))
            paragraph <- line("MATCH", id, args[1], kv("atoms", length(query$extra$atoms)),
                kv("bonds", length(query$extra$bonds)), kv("hits", length(matches)), kv("embeddings", total))
            for (r in matches) paragraph <- c(paragraph, line(r$m$name, kv("count", r$result$count),
                kv("unique", r$result$unique), kv("map", paste(r$result$mapping, collapse=","))))
            if (length(matches)) {
                top <- matches[[which.max(vapply(matches, function(r) r$result$count, 0L))]]
                paragraph <- c(paragraph, line("top", top$m$name, kv("count", top$result$count)))
            }
            paragraphs[[length(paragraphs)+1L]] <- paragraph
        } else if (kind == "CONTAINS") {
            contains <- contains+1L
            result <- embeddings(molecule_pattern(by_name[[args[1]]]), by_name[[args[2]]])
            text <- line("CONTAINS", id, args[1], args[2], kv("result", if (result$count > 0L) "yes" else "no"))
            if (result$count > 0L) {
                found <- found+1L
                text <- line(text, kv("count", result$count), kv("unique", result$unique),
                    kv("map", paste(result$mapping, collapse=",")))
            }
            paragraphs[[length(paragraphs)+1L]] <- text
        }
    }
    c(paragraphs, list(line("SUMMARY", kv("patterns", patterns), kv("hits", hits), kv("contains", contains), kv("found", found))))
}
similarity_paragraphs <- function(queries, molecules, by_name) {
    fingerprints <- line("FINGERPRINTS", kv("molecules", length(molecules)), "size=1024 depth=5")
    for (m in molecules) fingerprints <- c(fingerprints, line(m$name, kv("bits", length(m$bits)), kv("paths", m$paths)))
    paragraphs <- list(fingerprints)
    cache <- new.env(hash=TRUE, parent=emptyenv())
    similarity <- function(a, b) {
        key <- bond_key(a$order, b$order)
        value <- cache[[key]]
        if (is.null(value)) {
            value <- tanimoto(a$bits, b$bits)
            cache[[key]] <- value
        }
        value
    }
    for (query in queries) {
        kind <- query$kind
        id <- query$id
        args <- query$args
        paragraph <- character()
        if (kind == "MATRIX") {
            selected <- unname(by_name[args])
            paragraph <- line("MATRIX", id, kv("size", length(selected)))
            for (a in selected) paragraph <- c(paragraph, line("row", a$name,
                vapply(selected, function(b) fraction_text(similarity(a, b)), "")))
            best_i <- 1L
            best_j <- 2L
            best <- similarity(selected[[1]], selected[[2]])
            for (i in seq_along(selected)) if (i < length(selected)) for (j in seq.int(i+1L, length(selected))) {
                value <- similarity(selected[[i]], selected[[j]])
                if (fraction_compare(value, best) > 0) {
                    best_i <- i
                    best_j <- j
                    best <- value
                }
            }
            paragraph <- c(paragraph, line("best", selected[[best_i]]$name, selected[[best_j]]$name, fraction_text(best)))
        } else if (kind %in% c("NEAREST", "WITHIN")) {
            source <- by_name[[args[1]]]
            neighbors <- lapply(Filter(function(m) !identical(m, source), molecules),
                function(m) list(m=m, value=similarity(source, m)))
            ordered <- list()
            for (entry in neighbors) {
                position <- 1L
                while (position <= length(ordered) && fraction_compare(ordered[[position]]$value, entry$value) >= 0) {
                    position <- position+1L
                }
                ordered <- append(ordered, list(entry), after=position-1L)
            }
            result <- if (kind == "NEAREST") head(ordered, query$extra) else {
                Filter(function(r) fraction_compare(r$value, query$extra) >= 0, ordered)
            }
            paragraph <- if (kind == "NEAREST") line(kind, id, source$name, kv("count", length(result))) else {
                line(kind, id, source$name, kv("threshold", fraction_text(query$extra)), kv("count", length(result)))
            }
            for (i in seq_along(result)) paragraph <- c(paragraph, line(i, result[[i]]$m$name,
                fraction_text(result[[i]]$value), kv("common", result[[i]]$value[1])))
        } else if (kind == "COMPARE") {
            a <- by_name[[args[1]]]
            b <- by_name[[args[2]]]
            value <- similarity(a, b)
            paragraph <- line(kind, id, a$name, b$name, kv("bits", paste(c(length(a$bits), length(b$bits)), collapse=",")),
                kv("common", value[1]), kv("union", value[2]), kv("tanimoto", fraction_text(value)),
                kv("identical", if (a$canonical == b$canonical) "yes" else "no"))
        } else if (kind == "CLUSTER") {
            neighbors <- lapply(molecules, function(a) {
                vapply(Filter(function(b) !identical(a, b) && fraction_compare(similarity(a, b), query$extra) >= 0,
                    molecules), function(b) b$order, 0L)
            })
            ordered <- order(-lengths(neighbors), seq_along(molecules))
            assigned <- integer()
            clusters <- list()
            for (center in ordered) {
                if (center %in% assigned) next
                members <- c(center, setdiff(neighbors[[center]], assigned))
                clusters[[length(clusters)+1L]] <- members
                assigned <- union(assigned, members)
            }
            paragraph <- line(kind, id, kv("threshold", fraction_text(query$extra)),
                kv("clusters", length(clusters)), kv("singletons", sum(lengths(clusters) == 1L)))
            number <- 0L
            for (members in clusters) {
                if (length(members) == 1L) next
                number <- number+1L
                paragraph <- c(paragraph, line("cluster", number, kv("centroid", molecules[[members[1]]]$name),
                    kv("size", length(members)), kv("members", member_names(molecules[members]))))
            }
        } else next
        paragraphs[[length(paragraphs)+1L]] <- paragraph
    }
    paragraphs
}
paragraphs_text <- function(paragraphs) {
    paste0(paste(vapply(paragraphs, function(p) paste(p, collapse="\n"), ""), collapse="\n\n"), "\n")
}
main <- function() {
    elements <- read_elements()
    causes <- new.env(hash=TRUE, parent=emptyenv())
    read <- read_molecules(elements, causes)
    molecules <- read$molecules
    by_name <- setNames(molecules, vapply(molecules, function(m) m$name, ""))
    queries <- read_queries(elements, by_name, causes)
    reasons <- ls(causes, all.names=TRUE)
    counts <- vapply(reasons, function(r) causes[[r]], 0L)
    reasons <- reasons[order(-counts, reasons, method="radix")]
    causes_lines <- c(line("CAUSES", kv("kinds", length(reasons))),
        vapply(reasons, function(reason) kv(reason, causes[[reason]]), ""))
    reports <- list(properties.csv=paste0(paste(properties_lines(molecules), collapse="\n"), "\n"),
        canonical.txt=paragraphs_text(canonical_paragraphs(molecules)),
        rings.txt=paragraphs_text(ring_paragraphs(molecules)),
        substructure.txt=paragraphs_text(substructure_paragraphs(queries$queries, molecules, by_name)),
        similarity.txt=paragraphs_text(similarity_paragraphs(queries$queries, molecules, by_name)),
        errors.txt=paragraphs_text(list(read$paragraph, queries$paragraph, causes_lines)))
    dir.create("output", showWarnings=FALSE)
    for (name in names(reports)) {
        connection <- file(file.path("output", name), open="wb")
        writeChar(reports[[name]], connection, eos=NULL, useBytes=TRUE)
        close(connection)
    }
}
main()
