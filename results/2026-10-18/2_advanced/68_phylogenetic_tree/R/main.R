source("alignment.R")
source("distances.R")
source("tree_building.R")
source("parsimony.R")
source("tree_io.R")

NJ_METHODS <- c("NJ_P","NJ_JC","NJ_K2P")
METHODS <- c(NJ_METHODS,"ME","MP","CONSENSUS")
ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
square <- function(value) value*value
words <- function(...) paste(...,collapse=" ")
popcount <- function(value) {
  count <- 0L
  while (value != 0L) {
    count <- count+value %% 2L
    value <- value %/% 2L
  }
  count
}
symmetric_diff <- function(a,b) union(setdiff(a,b),setdiff(b,a))
support_count <- function(
    support,
    mask
) if (as.character(mask) %in% names(support)) support[[as.character(mask)]] else 0L
read_parameters <- function() {
  params <- list()
  for (line in readLines("input/params.txt")) {
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- fields[1L]
    params[[key]] <- if (key %in% c(
        "replicates",
        "seed",
        "max_missing_percent",
        "low_sites"
    )) as.integer(fields[2L]) else if (key == "saturation_distance") as.numeric(fields[2L]) else if (key == "exhaustive_taxa") fields[-1L] else fields[2L]
  }
  params
}
check_records <- function(records,maximum_missing) {
  n <- nchar(records[[1L]]$sequence)
  seen <- character()
  accepted <- rejected <- list()
  for (record in records) {
    reason <- if (record$name %in% seen) "duplicate name" else ""
    seen <- union(seen,record$name)
    characters <- strsplit(record$sequence,"",fixed=TRUE)[[1L]]
    if (reason == "") {
      invalid <- which(!(characters %in% names(BASE_SETS)))
      if (length(invalid)) reason <- paste(
          "invalid character",
          characters[invalid[1L]],
          "at column",
          invalid[1L]
      )
    }
    if (reason == "" && length(characters) != n) reason <- paste("length mismatch",length(characters))
    if (reason == "") {
      missing <- sum(characters %in% c("-","N"))
      if (100L*missing > maximum_missing*n) reason <- paste("too many missing",missing)
    }
    if (reason == "") accepted[[length(accepted)+1L]] <- list(
        name=record$name,
        sequence=characters
    ) else rejected[[length(rejected)+1L]] <- list(
        line=record$line,
        name=record$name,
        reason=reason
    )
  }
  list(accepted=accepted,rejected=rejected,length=n)
}
summary_lines <- function(records,rejected,taxon_names,sequences,patterns) {
  n <- length(sequences[[1L]])
  lines <- words(
      "INPUT records",
      length(records),
      "accepted",
      length(taxon_names),
      "rejected",
      length(rejected),
      "columns",
      n
  )
  for (r in rejected) lines <- c(lines,words("REJECT line",r$line,r$name,r$reason))
  columns <- lapply(
      seq_len(n),
      function(c) vapply(
          BASES,
          function(base) sum(vapply(sequences,function(sequence) sequence[c] == base,logical(1))),
          integer(1)
      )
  )
  composition <- integer(4L)
  for (i in seq_along(taxon_names)) {
    sequence <- sequences[[i]]
    counts <- vapply(BASES,function(base) sum(sequence == base),integer(1))
    bases <- sum(counts)
    unique_count <- sum(vapply(
        seq_len(n),
        function(c) sequence[c] %in% BASES && columns[[c]][match(
            sequence[c],
            BASES
        )] == 1L && sum(columns[[c]]) > 1L,
        logical(1)
    ))
    lines <- c(
        lines,
        words(
            "TAXON",
            taxon_names[i],
            "bases",
            bases,
            "ambiguous",
            sum(sequence %in% AMBIGUOUS),
            "missing",
            sum(sequence %in% c("-","N")),
            "unique",
            unique_count,
            "gc",
            real_text((counts[2L]+counts[3L])/bases,4L)
        )
    )
    composition <- composition+counts
  }
  classes <- classify_columns(sequences)
  lines <- c(
      lines,
      paste("COLUMNS",paste(c("constant","variable","informative","gapped","empty"),classes,collapse=" ")),
      words("PATTERNS",length(patterns$patterns)),
      paste(
          "COMPOSITION",
          paste(
              BASES,
              vapply(composition,function(value) real_text(value/sum(composition),4L),character(1)),
              collapse=" "
          )
      )
  )
  lines
}
matrix_lines <- function(taxon_names,matrix) {
  width <- max(nchar(taxon_names))
  vapply(
      seq_along(taxon_names),
      function(i) paste0(
          sprintf(paste0("%-",width,"s"),taxon_names[i]),
          " ",
          paste(vapply(matrix[i,],function(value) real_text(value,5L),character(1)),collapse=" ")
      ),
      character(1)
  )
}
parsimony_bounds <- function(patterns) {
  minima <- integer()
  maximal <- 0L
  for (i in seq_along(patterns$encoded)) {
    pattern <- patterns$encoded[[i]]
    valid <- (1:15)[vapply(1:15,function(mask) all(bitwAnd(mask,pattern) != 0L),logical(1))]
    minimum_value <- min(vapply(valid,popcount,integer(1)))-1L
    minima <- c(minima,minimum_value)
    greatest <- min(vapply(c(1L,2L,4L,8L),function(base) sum(bitwAnd(pattern,base) == 0L),integer(1)))
    maximal <- maximal+greatest*patterns$weights[i]
  }
  columns <- minima[patterns$columns]
  list(minimum=sum(columns),maximum=maximal,minima=columns)
}
bme_length <- function(tree,matrix) {
  taxa <- tree_taxa(tree)
  total <- 0
  for (i in seq_along(taxa)) {
    a <- taxa[i]
    steps <- path_distances(tree,a,unit=TRUE)
    if (i < length(taxa)) for (b in taxa[seq.int(
        i+1L,
        length(taxa)
    )]) total <- total+matrix[a,b]/(2^(steps[b]-1L))
  }
  total
}
stepwise <- function(taxa,n,patterns,outgroup) {
  tree <- star_tree(n,taxa[1:3])
  initial <- parsimony_score(tree,patterns,outgroup)
  current <- initial
  additions <- list()
  evaluated <- 0L
  if (length(taxa) > 3L) for (taxon in taxa[seq.int(4L,length(taxa))]) {
    best <- Inf
    chosen <- NULL
    selected_mask <- ties <- 0L
    for (edge in branches(tree,outgroup)) {
      candidate <- insert_taxon(tree,edge[2L],edge[3L],taxon)
      value <- parsimony_score(candidate,patterns,outgroup)
      evaluated <- evaluated+1L
      if (value < best) {
        best <- value
        chosen <- candidate
        selected_mask <- edge[1L]
        ties <- 1L
      } else if (value == best) ties <- ties+1L
    }
    tree <- chosen
    current <- best
    additions[[length(additions)+1L]] <- list(taxon=taxon,mask=selected_mask,value=current,ties=ties)
  }
  list(tree=tree,initial=initial,score=current,additions=additions,evaluated=evaluated,taxa=taxa)
}
hill_climb <- function(tree,objective,outgroup,value) {
  tree <- copy_tree(tree)
  evaluated <- 0L
  moves <- list()
  repeat {
    improved <- FALSE
    for (candidate in nni_candidates(tree,outgroup)) {
      candidate_value <- objective(candidate$tree)
      evaluated <- evaluated+1L
      if (candidate_value < value) {
        tree <- candidate$tree
        value <- candidate_value
        improved <- TRUE
        moves[[length(moves)+1L]] <- list(mask=candidate$mask,swap=candidate$swap,value=value)
        break
      }
    }
    if (!improved) break
  }
  list(tree=tree,value=value,moves=moves,evaluated=evaluated)
}
consensus_tree <- function(n,taxa,outgroup,clades) {
  tree <- new_tree(n,taxa)
  root <- internal_node(tree)
  nodes <- integer()
  for (mask in sort(clades)) nodes[as.character(mask)] <- internal_node(tree)
  for (mask in sort(as.integer(names(nodes)))) {
    containers <- setdiff(as.integer(names(nodes)),mask)
    containers <- containers[bitwAnd(containers,mask) == mask]
    parent <- if (length(containers)) nodes[[as.character(containers[which.min(vapply(
        containers,
        popcount,
        integer(1)
    ))])]] else root
    connect(tree,parent,nodes[[as.character(mask)]])
  }
  for (taxon in taxa) {
    containers <- as.integer(names(nodes))
    containers <- containers[bitwAnd(containers,bitwShiftL(1L,taxon-1L)) != 0L]
    parent <- if (length(containers)) nodes[[as.character(containers[which.min(vapply(
        containers,
        popcount,
        integer(1)
    ))])]] else root
    connect(tree,parent,taxon)
  }
  tree
}
exhaustive_search <- function(taxa,taxon_names,patterns,outgroup,matrix) {
  trees <- list(star_tree(length(taxon_names),taxa[1:3]))
  if (length(taxa) > 3L) for (taxon in taxa[seq.int(4L,length(taxa))]) {
    expanded <- list()
    for (tree in trees) for (edge in branches(tree,outgroup)) expanded[[length(expanded)+1L]] <- insert_taxon(
        tree,
        edge[2L],
        edge[3L],
        taxon
    )
    trees <- expanded
  }
  records <- list()
  histogram <- integer()
  for (tree in trees) {
    value <- parsimony_score(tree,patterns,outgroup)
    key <- as.character(value)
    histogram[key] <- if (key %in% names(histogram)) histogram[[key]]+1L else 1L
    records[[length(records)+1L]] <- list(
        tree=tree,
        score=value,
        bme=bme_length(tree,matrix),
        newick=newick(tree,taxon_names,outgroup),
        splits=split_set(root_tree(tree,outgroup))
    )
  }
  best_score <- min(as.integer(names(histogram)))
  optimal <- Filter(function(r) r$score == best_score,records)
  optimal <- optimal[order(vapply(optimal,function(r) r$newick,character(1)))]
  common <- optimal[[1L]]$splits
  for (record in optimal[-1L]) common <- intersect(common,record$splits)
  strict <- consensus_tree(length(taxon_names),taxa,outgroup,common)
  best_index <- order(
      vapply(records,function(r) r$bme,numeric(1)),
      vapply(records,function(r) r$newick,character(1))
  )[1L]
  second <- min(vapply(records[-best_index],function(r) r$bme,numeric(1)))
  initial <- stepwise(taxa,length(taxon_names),patterns,outgroup)
  heuristic <- hill_climb(
      initial$tree,
      function(t) parsimony_score(t,patterns,outgroup),
      outgroup,
      initial$score
  )
  list(
      taxa=taxa,
      records=records,
      histogram=histogram,
      best_score=best_score,
      optimal=optimal,
      strict=strict,
      best_bme=records[[best_index]],
      second_bme=second,
      heuristic=heuristic$value
  )
}
likelihood_sites <- function(tree,taxon_names,patterns,outgroup) {
  rooted <- root_tree(tree,outgroup)
  children <- child_order(rooted,taxon_names)
  transition <- vector("list",length(tree$adjacent))
  for (node in rooted$order[-1L]) {
    branch_length <- tree$adjacent[[node]][[as.character(rooted$parents[node])]]
    exponential <- exp(-(4*branch_length)/3)
    same <- 1/4+(3/4)*exponential
    different <- 1/4-(1/4)*exponential
    transition[[node]] <- matrix(different,4L,4L)
    diag(transition[[node]]) <- same
  }
  pattern_values <- numeric()
  for (pattern in patterns$encoded) {
    partial <- upward <- vector("list",length(tree$adjacent))
    for (node in rev(rooted$order)) {
      if (node <= tree$size) partial[[node]] <- vapply(
          0:3,
          function(base) if (bitwAnd(pattern[node],bitwShiftL(1L,base)) != 0L) 1 else 0,
          numeric(1)
      ) else {
        values <- rep(1,4L)
        for (child in children[[node]]) for (base in 1:4) values[base] <- values[base]*upward[[child]][base]
        partial[[node]] <- values
      }
      if (node != rooted$root) upward[[node]] <- vapply(
          1:4,
          function(a) ordered_sum(transition[[node]][a,]*partial[[node]]),
          numeric(1)
      )
    }
    pattern_values <- c(pattern_values,log(ordered_sum((1/4)*partial[[rooted$root]])))
  }
  pattern_values[patterns$columns]
}
likelihood_lines <- function(taxon_names,patterns,nj_trees,outgroup,main_method,low_count,site_logs) {
  n <- length(patterns$columns)
  lines <- words("LIKELIHOOD columns",n,"patterns",length(patterns$patterns))
  for (method in NJ_METHODS) {
    total <- ordered_sum(site_logs[[method]])
    lines <- c(lines,words("TREE",method,"loglik",real_text(total,4L),"per_site",real_text(total/n,4L)))
  }
  for (i in 1:2) for (j in seq.int(i+1L,3L)) {
    a <- NJ_METHODS[i]
    b <- NJ_METHODS[j]
    deltas <- site_logs[[a]]-site_logs[[b]]
    difference <- ordered_sum(deltas)
    mean <- difference/n
    se <- sqrt((n/(n-1L))*ordered_sum(square(deltas-mean)))
    lines <- c(
        lines,
        words(
            "KH",
            a,
            b,
            "difference",
            real_text(difference,4L),
            "se",
            real_text(se,4L),
            "z",
            real_text(difference/se,4L)
        )
    )
  }
  rounded <- vapply(site_logs[[main_method]],function(value) as.numeric(real_text(value,4L)),numeric(1))
  lowest <- order(rounded,seq_len(n))
  changes <- pattern_scores(nj_trees[[main_method]],patterns,outgroup)
  lines <- c(lines,words("LOWEST",main_method,"sites",low_count))
  for (c in lowest[seq_len(low_count)]) {
    index <- patterns$columns[c]
    lines <- c(
        lines,
        words(
            "SITE",
            c,
            "loglik",
            real_text(site_logs[[main_method]][c],4L),
            "changes",
            changes[index],
            "pattern",
            patterns$patterns[index]
        )
    )
  }
  lines
}
bootstrap <- function(taxon_names,sequences,params,main_tree,main_matrix,outgroup) {
  n <- length(taxon_names)
  l <- length(sequences[[1L]])
  replicates <- params$replicates
  state <- as.numeric(params$seed)
  support <- integer()
  main_splits <- split_set(root_tree(main_tree,outgroup))
  lines <- words("BOOTSTRAP model",params$model,"replicates",replicates,"seed",sprintf("%.0f",state))
  identical <- 0L
  for (replicate in seq_len(replicates)) {
    weights <- integer(l)
    for (unused in seq_len(l)) {
      state <- (48271*state) %% 2147483647
      index <- state %% l+1L
      weights[index] <- weights[index]+1L
    }
    matrix <- build_matrix(all_pairs(sequences,weights),n,params$model,params$saturation_distance)$matrix
    tree <- neighbor_joining(matrix,seq_len(n))
    splits <- split_set(root_tree(tree,outgroup))
    for (mask in splits) support[as.character(mask)] <- support_count(support,mask)+1L
    difference <- length(symmetric_diff(splits,main_splits))
    identical <- identical+as.integer(difference == 0L)
    lines <- c(lines,words("REPLICATE",replicate,"distinct",sum(weights > 0L),"rf",difference))
  }
  lines <- c(lines,words("IDENTICAL",identical))
  masks <- main_splits[order(vapply(main_splits,function(mask) symbols(mask,n),character(1)))]
  for (mask in masks) lines <- c(lines,words("SUPPORT",symbols(mask,n),support_count(support,mask)))
  masks <- as.integer(names(support))
  masks <- masks[order(-support,vapply(masks,function(mask) symbols(mask,n),character(1)))]
  for (mask in masks) lines <- c(lines,words("SPLIT",symbols(mask,n),support_count(support,mask)))
  majority <- as.integer(names(support)[2L*support > replicates])
  consensus <- consensus_tree(n,seq_len(n),outgroup,majority)
  lines <- c(lines,paste("CONSENSUS",newick(consensus,taxon_names,outgroup,support=support)))
  for (taxon in seq_len(n)) {
    if (taxon == outgroup) next
    tree <- neighbor_joining(main_matrix,setdiff(seq_len(n),taxon))
    reduced <- unique(bitwAnd(main_splits,bitwNot(bitwShiftL(1L,taxon-1L))))
    sizes <- vapply(reduced,popcount,integer(1))
    reduced <- reduced[sizes >= 2L & sizes <= n-3L]
    lines <- c(
        lines,
        words(
            "JACKKNIFE",
            taxon_names[taxon],
            "rf",
            length(symmetric_diff(split_set(root_tree(tree,outgroup)),reduced))
        )
    )
  }
  list(consensus=consensus,support=support,lines=lines)
}
clock_lines <- function(taxon_names,sequences,outgroup,main_method,tree) {
  ingroup <- setdiff(seq_along(taxon_names),outgroup)
  pairs <- character()
  rejected <- 0L
  for (i in seq_len(length(ingroup)-1L)) for (j in seq.int(i+1L,length(ingroup))) {
    a <- ingroup[i]
    b <- ingroup[j]
    m1 <- m2 <- 0L
    for (c in seq_along(sequences[[a]])) {
      x <- sequences[[a]][c]
      y <- sequences[[b]][c]
      o <- sequences[[outgroup]][c]
      if (x %in% BASES && y %in% BASES && o %in% BASES && x != y) {
        m1 <- m1+as.integer(y == o)
        m2 <- m2+as.integer(x == o)
      }
    }
    reject <- 1000L*square(m1-m2) > 3841L*(m1+m2)
    rejected <- rejected+as.integer(reject)
    chi <- if (m1+m2 == 0L) "-" else real_text(square(m1-m2)/(m1+m2),4L)
    pairs <- c(
        pairs,
        words("RRT",taxon_names[a],taxon_names[b],"m1",m1,"m2",m2,"chi2",chi,if (reject) "reject" else "ok")
    )
  }
  lines <- c(
      words("RELATIVE_RATE outgroup",taxon_names[outgroup],"pairs",length(pairs),"rejected",rejected),
      pairs
  )
  paths <- path_distances(tree,root_tree(tree,outgroup)$root)
  mean <- ordered_sum(paths[ingroup])/length(ingroup)
  sd <- sqrt(ordered_sum(square(paths[ingroup]-mean))/(length(ingroup)-1L))
  lines <- c(
      lines,
      words(
          "ROOT_TO_TIP",
          main_method,
          "mean",
          real_text(mean,5L),
          "sd",
          real_text(sd,5L),
          "cv",
          real_text(sd/mean,4L)
      )
  )
  c(lines,vapply(ingroup,function(t) words("TIP",taxon_names[t],real_text(paths[t],5L)),character(1)))
}
quartet_topologies <- function(splits,n) {
  result <- integer()
  for (a in seq_len(n-3L)) for (b in seq.int(a+1L,n-2L)) for (c in seq.int(
      b+1L,
      n-1L
  )) for (d in seq.int(c+1L,n)) {
    quartet <- sum(bitwShiftL(1L,c(a,b,c,d)-1L))
    topology <- 0L
    others <- c(b,c,d)
    for (number in seq_along(others)) {
      side <- bitwOr(bitwShiftL(1L,a-1L),bitwShiftL(1L,others[number]-1L))
      if (any(bitwAnd(splits,quartet) %in% c(side,bitwXor(quartet,side)))) {
        topology <- number
        break
      }
    }
    result <- c(result,topology)
  }
  result
}
comparison_lines <- function(
    taxon_names,
    patterns,
    trees,
    matrices,
    main_matrix,
    main_method,
    outgroup,
    support,
    replicates,
    nj_scores,
    mp_score,
    mp_changes,
    site_logs,
    patristic
) {
  n <- length(taxon_names)
  splits <- setNames(lapply(METHODS,function(method) split_set(root_tree(trees[[method]],outgroup))),METHODS)
  lines <- character()
  for (method in METHODS) {
    tree <- trees[[method]]
    supported <- sum(vapply(
        splits[[method]],
        function(mask) 2L*support_count(support,mask) > replicates,
        logical(1)
    ))
    score <- bme <- branch_length <- negative <- residual <- likelihood <- "-"
    if (method != "CONSENSUS") {
      value <- if (method %in% NJ_METHODS) nj_scores[[method]] else if (method == "MP") mp_score else parsimony_score(
          tree,
          patterns,
          outgroup
      )
      score <- as.character(value)
      bme <- real_text(bme_length(tree,main_matrix),5L)
    }
    if (method %in% NJ_METHODS) {
      branch_length <- real_text(
          ordered_sum(vapply(
              branches(tree,outgroup),
              function(edge) tree$adjacent[[edge[2L]]][[as.character(edge[3L])]],
              numeric(1)
          )),
          5L
      )
      negative <- as.character(tree$negative)
      matrix <- matrices[[substring(method,4L)]]
      errors <- numeric()
      for (a in seq_len(n-1L)) for (b in seq.int(a+1L,n)) errors <- c(
          errors,
          square(matrix[a,b]-patristic[[method]][a,b])
      )
      residual <- real_text(ordered_sum(errors),6L)
      likelihood <- real_text(ordered_sum(site_logs[[method]]),4L)
    } else if (method == "MP") branch_length <- real_text(mp_score/length(patterns$columns),5L)
    lines <- c(
        lines,
        words(
            "TREE",
            method,
            "splits",
            length(splits[[method]]),
            "supported",
            supported,
            "parsimony",
            score,
            "bme",
            bme,
            "length",
            branch_length,
            "negative",
            negative,
            "sse",
            residual,
            "loglik",
            likelihood
        )
    )
  }
  lines <- c(lines,paste("RF",paste(METHODS,collapse=" ")))
  for (first in METHODS) lines <- c(
      lines,
      words(
          first,
          paste(
              vapply(
                  METHODS,
                  function(second) length(symmetric_diff(splits[[first]],splits[[second]])),
                  integer(1)
              ),
              collapse=" "
          )
      )
  )
  quartets <- setNames(lapply(METHODS,function(method) quartet_topologies(splits[[method]],n)),METHODS)
  lines <- c(lines,paste("QUARTET",paste(METHODS,collapse=" ")))
  for (first in METHODS) lines <- c(
      lines,
      words(
          first,
          paste(
              vapply(METHODS,function(second) sum(quartets[[first]] != quartets[[second]]),integer(1)),
              collapse=" "
          )
      )
  )
  all_clades <- unique(unlist(splits,use.names=FALSE))
  lengths <- branch_lengths(root_tree(trees[[main_method]],outgroup))
  changes <- integer()
  for (edge in branches(trees$MP,outgroup)) changes[as.character(edge[1L])] <- mp_changes[[paste(
      min(edge[2:3]),
      max(edge[2:3]),
      sep=","
  )]]
  for (mask in all_clades[order(vapply(all_clades,function(mask) symbols(mask,n),character(1)))]) {
    marks <- paste(
        vapply(METHODS,function(method) if (mask %in% splits[[method]]) "+" else "-",character(1)),
        collapse=""
    )
    key <- as.character(mask)
    length_text <- if (key %in% names(lengths)) real_text(lengths[[key]],5L) else "-"
    change <- if (key %in% names(changes)) as.character(changes[[key]]) else "-"
    lines <- c(
        lines,
        words(
            "CLADE",
            symbols(mask,n),
            "support",
            support_count(support,mask),
            "trees",
            marks,
            "length",
            length_text,
            "changes",
            change
        )
    )
  }
  lines
}
hypothesis_lines <- function(taxon_names,trees,outgroup,support,exhaustive) {
  ingroup <- bitwXor(bitwShiftL(1L,length(taxon_names))-1L,bitwShiftL(1L,outgroup-1L))
  exhaustive_ingroup <- sum(bitwShiftL(1L,setdiff(exhaustive$taxa,outgroup)-1L))
  splits <- setNames(lapply(METHODS,function(method) split_set(root_tree(trees[[method]],outgroup))),METHODS)
  lines <- character()
  for (line in readLines("input/clades.txt")) {
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    hypothesis <- fields[1L]
    members <- fields[-1L]
    unknown <- members[!(members %in% taxon_names)]
    if (length(unknown)) {
      lines <- c(lines,words("INVALID",hypothesis,"unknown taxon",unknown[1L]))
      next
    }
    if (taxon_names[outgroup] %in% members) {
      lines <- c(lines,words("INVALID",hypothesis,"contains outgroup"))
      next
    }
    mask <- sum(bitwShiftL(1L,match(members,taxon_names)-1L))
    lines <- c(lines,words("CLADE",hypothesis,"taxa",popcount(mask),"support",support_count(support,mask)))
    for (method in METHODS) {
      containers <- union(splits[[method]],ingroup)
      containers <- containers[bitwAnd(containers,mask) == mask]
      common <- containers[which.min(vapply(containers,popcount,integer(1)))]
      intruders <- taxon_names[bitwAnd(
          bitwAnd(common,bitwNot(mask)),
          bitwShiftL(1L,seq_along(taxon_names)-1L)
      ) != 0L]
      lines <- c(
          lines,
          words(
              "TEST",
              hypothesis,
              method,
              "monophyletic",
              if (common == mask) "yes" else "no",
              "mrca",
              popcount(common),
              "intruders",
              if (length(intruders)) paste(intruders,collapse=",") else "-"
          )
      )
    }
    subset <- bitwAnd(mask,exhaustive_ingroup)
    if (!(popcount(subset) >= 2L && popcount(subset) < popcount(exhaustive_ingroup))) {
      lines <- c(lines,words("SUBSET",hypothesis,"untestable"))
      next
    }
    included <- Filter(function(r) subset %in% r$splits,exhaustive$records)
    excluded <- Filter(function(r) !(subset %in% r$splits),exhaustive$records)
    lines <- c(
        lines,
        words(
            "SUBSET",
            hypothesis,
            "taxa",
            popcount(subset),
            "with",
            min(vapply(included,function(r) r$score,integer(1))),
            "without",
            min(vapply(excluded,function(r) r$score,integer(1))),
            "bme_with",
            real_text(min(vapply(included,function(r) r$bme,numeric(1))),5L),
            "bme_without",
            real_text(min(vapply(excluded,function(r) r$bme,numeric(1))),5L)
        )
    )
  }
  lines
}
distance_lines <- function(
    taxon_names,
    pairs,
    matrices,
    saturated,
    main_method,
    patristic,
    me_start,
    me,
    exhaustive
) {
  totals <- integer(3L)
  pair_block <- character()
  for (pair in pairs) {
    a <- pair[1L]
    b <- pair[2L]
    pair_block <- c(
        pair_block,
        words(
            "PAIR",
            taxon_names[a],
            taxon_names[b],
            "sites",
            pair[3L],
            "transitions",
            pair[4L],
            "transversions",
            pair[5L]
        )
    )
    totals <- totals+pair[3:5]
  }
  pair_block <- c(
      pair_block,
      words("TOTAL sites",totals[1L],"transitions",totals[2L],"transversions",totals[3L])
  )
  blocks <- list(pair_block)
  for (model in MODELS) {
    block <- c(paste("MODEL",model),matrix_lines(taxon_names,matrices[[model]]))
    for (pair in saturated[[model]]) block <- c(
        block,
        words("SATURATED",taxon_names[pair[1L]],taxon_names[pair[2L]],"sites",pair[3L])
    )
    blocks[[length(blocks)+1L]] <- block
  }
  blocks[[length(blocks)+1L]] <- c(
      paste("PATRISTIC",main_method),
      matrix_lines(taxon_names,patristic[[main_method]])
  )
  evolution <- words("ME start",main_method,"length",real_text(me_start,5L))
  for (move in me$moves) evolution <- c(
      evolution,
      words(
          "NNI edge",
          symbols(move$mask,length(taxon_names)),
          "swap",
          move$swap,
          "length",
          real_text(move$value,5L)
      )
  )
  evolution <- c(
      evolution,
      words("ME moves",length(me$moves),"evaluated",me$evaluated,"length",real_text(me$value,5L))
  )
  best <- exhaustive$best_bme
  evolution <- c(
      evolution,
      words(
          "EXHAUSTIVE taxa",
          length(exhaustive$taxa),
          "trees",
          length(exhaustive$records),
          "best",
          real_text(best$bme,5L),
          "second",
          real_text(exhaustive$second_bme,5L)
      ),
      words("BEST",best$newick,"parsimony",best$score)
  )
  blocks[[length(blocks)+1L]] <- evolution
  lines <- character()
  for (block in blocks) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,block)
  }
  lines
}
score_line <- function(method,score,minimum_value,maximum_value) words(
    "TREE",
    method,
    "score",
    score,
    "ci",
    real_text(minimum_value/score,4L),
    "ri",
    real_text((maximum_value-score)/(maximum_value-minimum_value),4L)
)
parsimony_lines <- function(
    taxon_names,
    outgroup,
    minimum_value,
    maximum_value,
    minima,
    nj_scores,
    initial,
    search,
    ancestors,
    changes,
    exhaustive
) {
  lines <- words("BOUNDS minimum",minimum_value,"maximum",maximum_value)
  for (method in NJ_METHODS) lines <- c(
      lines,
      score_line(method,nj_scores[[method]],minimum_value,maximum_value)
  )
  lines <- c(lines,words("START",paste(taxon_names[initial$taxa[1:3]],collapse=" "),"score",initial$initial))
  for (addition in initial$additions) lines <- c(
      lines,
      words(
          "ADD",
          taxon_names[addition$taxon],
          "edge",
          symbols(addition$mask,length(taxon_names)),
          "score",
          addition$value,
          "ties",
          addition$ties
      )
  )
  lines <- c(lines,words("STEPWISE score",initial$score,"evaluated",initial$evaluated))
  for (move in search$moves) lines <- c(
      lines,
      words("NNI edge",symbols(move$mask,length(taxon_names)),"swap",move$swap,"score",move$value)
  )
  lines <- c(
      lines,
      words("SEARCH moves",length(search$moves),"evaluated",search$evaluated,"score",search$value),
      score_line("MP",search$value,minimum_value,maximum_value),
      paste("MP",newick(search$tree,taxon_names,outgroup,lengths=TRUE))
  )
  for (value in 0:max(changes)) lines <- c(lines,words("CHANGES",value,"columns",sum(changes == value)))
  lines <- c(lines,words("HOMOPLASY columns",sum(changes > minima),"extra",search$value-minimum_value))
  rooted <- root_tree(search$tree,outgroup)
  records <- lapply(
      names(ancestors),
      function(node) list(
          symbol=symbols(
              if (as.integer(node) == rooted$root) rooted$ingroup else rooted$masks[as.integer(node)],
              length(taxon_names)
          ),
          sequence=ancestors[[node]]
      )
  )
  records <- records[order(vapply(records,function(r) r$symbol,character(1)))]
  for (record in records) lines <- c(lines,words("ANCESTOR",record$symbol,record$sequence))
  lines <- c(
      lines,
      "",
      words(
          "EXHAUSTIVE taxa",
          length(exhaustive$taxa),
          "trees",
          length(exhaustive$records),
          "best",
          exhaustive$best_score,
          "optimal",
          length(exhaustive$optimal)
      )
  )
  for (value in sort(as.integer(names(exhaustive$histogram)))) lines <- c(
      lines,
      words("SCORE",value,"trees",exhaustive$histogram[[as.character(value)]])
  )
  for (record in exhaustive$optimal) lines <- c(
      lines,
      words("OPTIMAL",record$newick,"bme",real_text(record$bme,5L))
  )
  c(
      lines,
      paste("STRICT",newick(exhaustive$strict,taxon_names,outgroup)),
      words(
          "HEURISTIC score",
          exhaustive$heuristic,
          "optimal",
          if (exhaustive$heuristic == exhaustive$best_score) "yes" else "no"
      )
  )
}
main <- function() {
  invisible(Sys.setlocale("LC_COLLATE","C"))
  params <- read_parameters()
  records <- read_fasta()
  checked <- check_records(records,params$max_missing_percent)
  accepted <- checked$accepted
  rejected <- checked$rejected
  l <- checked$length
  taxon_names <- vapply(accepted,function(r) r$name,character(1))
  sequences <- lapply(accepted,function(r) r$sequence)
  n <- length(taxon_names)
  outgroup <- match(params$outgroup,taxon_names)
  patterns <- compress_patterns(sequences)
  pairs <- all_pairs(sequences,rep(1L,l))
  matrices <- saturated <- nj_trees <- list()
  for (i in seq_along(MODELS)) {
    model <- MODELS[i]
    method <- NJ_METHODS[i]
    result <- build_matrix(pairs,n,model,params$saturation_distance)
    matrices[[model]] <- result$matrix
    saturated[[model]] <- result$saturated
    nj_trees[[method]] <- neighbor_joining(matrices[[model]],seq_len(n))
  }
  main_method <- paste0("NJ_",params$model)
  main_tree <- nj_trees[[main_method]]
  main_matrix <- matrices[[params$model]]
  me_start <- bme_length(main_tree,main_matrix)
  me <- hill_climb(main_tree,function(t) bme_length(t,main_matrix),outgroup,me_start)
  addition_order <- c(outgroup,setdiff(seq_len(n),outgroup))
  initial <- stepwise(addition_order,n,patterns,outgroup)
  mp <- hill_climb(initial$tree,function(t) parsimony_score(t,patterns,outgroup),outgroup,initial$score)
  reconstructed <- reconstruct(mp$tree,patterns,outgroup)
  branch_changes <- reconstructed$branch_changes
  for (key in names(branch_changes)) {
    edge <- as.integer(strsplit(key,",",fixed=TRUE)[[1L]])
    connect(mp$tree,edge[1L],edge[2L],branch_changes[[key]]/l)
  }
  bounds <- parsimony_bounds(patterns)
  nj_scores <- setNames(
      lapply(NJ_METHODS,function(method) parsimony_score(nj_trees[[method]],patterns,outgroup)),
      NJ_METHODS
  )
  exhaustive_taxa <- c(outgroup,which(seq_len(n) != outgroup & taxon_names %in% params$exhaustive_taxa))
  exhaustive <- exhaustive_search(exhaustive_taxa,taxon_names,patterns,outgroup,main_matrix)
  site_logs <- setNames(
      lapply(NJ_METHODS,function(method) likelihood_sites(nj_trees[[method]],taxon_names,patterns,outgroup)),
      NJ_METHODS
  )
  resampling <- bootstrap(taxon_names,sequences,params,main_tree,main_matrix,outgroup)
  support <- resampling$support
  trees <- c(nj_trees,list(ME=me$tree,MP=mp$tree,CONSENSUS=resampling$consensus))
  patristic <- setNames(lapply(NJ_METHODS,function(method) patristic_matrix(nj_trees[[method]])),NJ_METHODS)
  newicks <- diagrams <- character()
  for (method in METHODS) {
    tree <- trees[[method]]
    newicks <- c(
        newicks,
        paste(
            method,
            newick(
                tree,
                taxon_names,
                outgroup,
                lengths=method %in% c(NJ_METHODS,"MP"),
                support=if (method == "CONSENSUS") support else NULL
            )
        )
    )
    if (length(diagrams)) diagrams <- c(diagrams,"")
    diagrams <- c(diagrams,paste("TREE",method),cladogram(tree,taxon_names,outgroup,support))
  }
  outputs <- list(
      "summary.txt"=summary_lines(records,rejected,taxon_names,sequences,patterns),
      "distances.txt"=distance_lines(
          taxon_names,
          pairs,
          matrices,
          saturated,
          main_method,
          patristic,
          me_start,
          me,
          exhaustive
      ),
      "trees.nwk"=newicks,
      "cladograms.txt"=diagrams,
      "parsimony.txt"=parsimony_lines(
          taxon_names,
          outgroup,
          bounds$minimum,
          bounds$maximum,
          bounds$minima,
          nj_scores,
          initial,
          mp,
          reconstructed$ancestors,
          reconstructed$column_changes,
          exhaustive
      ),
      "likelihood.txt"=likelihood_lines(
          taxon_names,
          patterns,
          nj_trees,
          outgroup,
          main_method,
          params$low_sites,
          site_logs
      ),
      "bootstrap.txt"=resampling$lines,
      "clock.txt"=clock_lines(taxon_names,sequences,outgroup,main_method,main_tree),
      "comparison.txt"=comparison_lines(
          taxon_names,
          patterns,
          trees,
          matrices,
          main_matrix,
          main_method,
          outgroup,
          support,
          params$replicates,
          nj_scores,
          mp$value,
          branch_changes,
          site_logs,
          patristic
      ),
      "hypotheses.txt"=hypothesis_lines(taxon_names,trees,outgroup,support,exhaustive)
  )
  for (filename in names(outputs)) write_lines(filename,outputs[[filename]])
}
main()
