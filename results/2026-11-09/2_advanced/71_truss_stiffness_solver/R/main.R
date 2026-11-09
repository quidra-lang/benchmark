source("model_io.R")
source("assembly.R")
source("solver.R")
source("postprocess.R")
source("design.R")

words <- function(...) paste(...,collapse=" ")
ordered_total <- function(items) {
  value <- 0
  for (item in items) value <- value+item
  value
}
format_real <- function(value,digits=4L) {
  text <- sprintf(paste0("%.",digits,"f"),value)
  text[startsWith(text,"-") & as.numeric(text) == 0] <- substring(
      text[startsWith(text,"-") & as.numeric(text) == 0],
      2L
  )
  text
}
rounded <- function(value) as.numeric(format_real(value))
extreme_index <- function(
    entries,
    minimum_value=FALSE
) if (minimum_value) which.min(rounded(entries)) else which.max(rounded(entries))
renumber <- function(nodes,members) {
  neighbors <- lapply(nodes,function(n) integer())
  for (m in members) {
    neighbors[[m$start]] <- union(neighbors[[m$start]],m$finish)
    neighbors[[m$finish]] <- union(neighbors[[m$finish]],m$start)
  }
  ids <- vapply(nodes,function(n) n$id,integer(1))
  degrees <- lengths(neighbors)
  queue <- order(degrees,ids)[1L]
  visited <- queue
  head <- 1L
  while (head <= length(queue)) {
    v <- queue[head]
    head <- head+1L
    following <- setdiff(neighbors[[v]],visited)
    following <- following[order(degrees[following],ids[following])]
    queue <- c(queue,following)
    visited <- c(visited,following)
  }
  list(order=rev(queue),neighbors=neighbors)
}
numbering_metrics <- function(numbers,neighbors,members) {
  bandwidth <- max(vapply(members,function(m) abs(numbers[m$start]-numbers[m$finish]),integer(1)))
  profile <- sum(vapply(
      seq_along(neighbors),
      function(v) numbers[v]-min(numbers[c(v,neighbors[[v]])]),
      integer(1)
  ))
  c(bandwidth,profile)
}
truss_context <- function(model) {
  a <- new.env(parent=emptyenv())
  a$model <- model
  a$nodes <- model$nodes
  a$members <- model$members
  a$settings <- model$settings
  numbering <- renumber(a$nodes,a$members)
  a$order <- numbering$order
  a$neighbors <- numbering$neighbors
  a$numbers <- integer(length(a$nodes))
  a$numbers[a$order] <- seq_along(a$nodes)-1L
  a$node_dofs <- lapply(a$numbers,function(n) c(2L*n+1L,2L*n+2L))
  a$degrees <- 2L*length(a$nodes)
  a$owners <- vector("list",a$degrees)
  for (v in seq_along(a$nodes)) for (axis in seq_len(2L)) a$owners[[a$node_dofs[[v]][axis]]] <- c(v,axis)
  a$prescribed <- numeric(a$degrees)
  a$support_directions <- list()
  for (support in model$supports) for (axis in seq_len(2L)) if (support$fixed[axis] == 1L) {
    d <- a$node_dofs[[support$node]][axis]
    a$prescribed[d] <- support$prescribed[axis]
    a$support_directions[[length(a$support_directions)+1L]] <- c(support$node,axis,d)
  }
  a$restrained <- sort(vapply(a$support_directions,function(d) d[3L],integer(1)))
  a$free <- setdiff(seq_len(a$degrees),a$restrained)
  a$geometry <- member_geometry(a$nodes,a$members,a$node_dofs)
  a$group_order <- unique(vapply(a$members,function(m) m$group,character(1)))
  a$groups <- lapply(
      a$group_order,
      function(name) which(vapply(a$members,function(m) m$group == name,logical(1)))
  )
  a$definitions <- setNames(model$combinations,vapply(model$combinations,function(c) c$name,character(1)))
  a$result_order <- c(
      lapply(model$cases,function(c) list(kind="case",name=c$name)),
      lapply(model$combinations,function(c) list(kind="combination",name=c$name))
  )
  a$deck <- a$settings$deck
  a$deck_x <- vapply(a$nodes[a$deck],function(n) n$x,integer(1))
  a$units <- vector("list",length(a$nodes))
  a
}
build_system <- function(a,choices,removed=0L) {
  properties <- member_properties(a$model,choices,a$geometry)
  matrix <- assemble(a$geometry,properties,a$degrees,removed)
  free_matrix <- matrix[a$free,a$free,drop=FALSE]
  c(
      list(properties=properties,matrix=matrix,free_matrix=free_matrix,removed=removed),
      factor_cholesky(free_matrix,a$free)
  )
}
displacement <- function(a,system,force,settlement=FALSE) {
  result <- numeric(a$degrees)
  if (settlement) result[a$restrained] <- a$prescribed[a$restrained]
  right <- numeric(length(a$free))
  for (i in seq_along(a$free)) {
    d <- a$free[i]
    value <- force[d]
    for (r in a$restrained) value <- value-system$matrix[d,r]*result[r]
    right[i] <- value
  }
  result[a$free] <- solve_cholesky(system$lower,right)
  result
}
case_result <- function(a,system,case) {
  loading <- load_vectors(case,a$geometry,system$properties,a$node_dofs,a$degrees,system$removed)
  d <- displacement(a,system,loading$total,loading$settlement)
  forces <- axial_forces(a$geometry,system$properties,d,loading$temperature,system$removed)
  reactions <- support_reactions(system$matrix,d,loading$total,a$restrained)
  list(name=case$name,displacement=d,forces=forces,reactions=reactions,external=loading$external)
}
analyze <- function(a,system,combination=NULL) {
  combinations <- if (is.null(combination)) a$model$combinations else list(combination)
  needed <- unique(unlist(
      lapply(combinations,function(c) vapply(c$terms,function(t) t$name,character(1))),
      use.names=FALSE
  ))
  results <- list()
  for (case in a$model$cases) if (is.null(combination) || case$name %in% needed) results[[case$name]] <- case_result(
      a,
      system,
      case
  )
  for (item in combinations) results[[item$name]] <- superpose(item,results)
  results
}
unit_result <- function(a,node) {
  if (is.null(a$units[[node]])) {
    force <- numeric(a$degrees)
    force[a$node_dofs[[node]][2L]] <- -1000
    d <- displacement(a,a$final_system,force)
    forces <- axial_forces(a$geometry,a$properties,d,numeric(length(a$members)))
    reactions <- support_reactions(a$final_system$matrix,d,force,a$restrained)
    a$units[[node]] <- list(name="unit",displacement=d,forces=forces,reactions=reactions,external=force)
  }
  a$units[[node]]
}
design_sections <- function(a) {
  choices <- vapply(a$members,function(m) m$section,integer(1))
  history <- character()
  for (round_number in seq_len(10L)) {
    system <- build_system(a,choices)
    results <- analyze(a,system)
    combinations <- lapply(a$model$combinations,function(c) results[[c$name]])
    limits <- vapply(
        seq_along(a$members),
        slenderness_limit,
        numeric(1),
        combinations=combinations,
        limits=a$settings$slenderness
    )
    utilizations <- lapply(
        seq_along(a$members),
        function(i) vapply(
            combinations,
            function(r) utilization(r$forces[i],system$properties[[i]],a$geometry[[i]]),
            numeric(1)
        )
    )
    entries <- unlist(utilizations,use.names=FALSE)
    selected <- extreme_index(entries)
    member <- (selected-1L) %/% length(combinations)+1L
    governing_case <- (selected-1L) %% length(combinations)+1L
    weight <- ordered_total(vapply(
        seq_along(a$members),
        function(i) member_weight(system$properties[[i]],a$geometry[[i]]),
        numeric(1)
    ))
    changes <- list()
    for (group in seq_along(a$groups)) {
      indices <- a$groups[[group]]
      chosen <- select_section(indices,a$model$sections,system$properties,a$geometry,combinations,limits)
      current <- choices[indices[1L]]
      if (chosen != current) {
        group_entries <- unlist(utilizations[indices],use.names=FALSE)
        changes[[length(changes)+1L]] <- list(
            group=group,
            current=current,
            chosen=chosen,
            largest=group_entries[extreme_index(group_entries)]
        )
      }
    }
    history <- c(
        history,
        words(
            "round",
            round_number,
            "weight",
            format_real(weight/1000),
            "max_utilization",
            format_real(entries[selected]),
            "at",
            a$members[[member]]$id,
            combinations[[governing_case]]$name,
            "changes",
            length(changes)
        )
    )
    for (change in changes) history <- c(
        history,
        words(
            "change",
            a$group_order[change$group],
            a$model$sections[[change$current]]$name,
            a$model$sections[[change$chosen]]$name,
            "utilization",
            format_real(change$largest)
        )
    )
    converged <- !length(changes)
    if (converged || round_number == 10L) break
    for (change in changes) choices[a$groups[[change$group]]] <- change$chosen
  }
  a$choices <- choices
  a$final_system <- system
  a$properties <- system$properties
  a$results <- results
  a$combinations <- combinations
  a$limits <- limits
  a$utilizations <- utilizations
  a$weight <- weight
  a$governing_cases <- vapply(utilizations,extreme_index,integer(1))
  a$governing <- vapply(
      seq_along(utilizations),
      function(i) utilizations[[i]][a$governing_cases[i]],
      numeric(1)
  )
  c(history,words("result",if (converged) "converged" else "not_converged","rounds",round_number))
}
design_report <- function(a,history) {
  lines <- history
  for (group in seq_along(a$groups)) {
    indices <- a$groups[[group]]
    i <- indices[extreme_index(a$governing[indices])]
    section <- a$model$sections[[a$choices[indices[1L]]]]$name
    lines <- c(
        lines,
        words(
            "group",
            a$group_order[group],
            "section",
            section,
            "members",
            length(indices),
            "utilization",
            format_real(a$governing[i]),
            "at",
            a$members[[i]]$id
        )
    )
  }
  for (i in seq_along(a$members)) {
    m <- a$members[[i]]
    slender <- slenderness(a$properties[[i]],a$geometry[[i]])
    limit <- a$limits[i]
    verdict <- if (a$governing[i] <= 1 && slender <= limit) "ok" else "over"
    lines <- c(
        lines,
        words(
            "member",
            m$id,
            "group",
            m$group,
            "section",
            a$model$sections[[a$choices[i]]]$name,
            "utilization",
            format_real(a$governing[i]),
            "governing",
            a$combinations[[a$governing_cases[i]]]$name,
            "slenderness",
            format_real(slender),
            "limit",
            format_real(limit),
            verdict
        )
    )
  }
  ranking <- order(-rounded(a$governing),seq_along(a$members))
  for (rank in seq_len(min(5L,length(ranking)))) {
    i <- ranking[rank]
    lines <- c(lines,words("rank",rank,"member",a$members[[i]]$id,"utilization",format_real(a$governing[i])))
  }
  for (i in seq_along(a$members)) {
    entries <- vapply(a$combinations,function(r) r$forces[i]/1000,numeric(1))
    hi <- extreme_index(entries)
    lo <- extreme_index(entries,TRUE)
    lines <- c(
        lines,
        words(
            "envelope",
            a$members[[i]]$id,
            "max",
            format_real(entries[hi]),
            a$combinations[[hi]]$name,
            "min",
            format_real(entries[lo]),
            a$combinations[[lo]]$name
        )
    )
  }
  for (i in seq_along(a$model$sections)) {
    indices <- which(a$choices == i)
    if (!length(indices)) next
    span <- ordered_total(vapply(a$geometry[indices],function(g) g$length,numeric(1)))
    lines <- c(
        lines,
        words("section",a$model$sections[[i]]$name,"members",length(indices),"length",format_real(span))
    )
  }
  c(lines,paste("weight",format_real(a$weight/1000)))
}
magnitudes <- function(a,result) vapply(
    a$node_dofs,
    function(d) sqrt(result$displacement[d[1L]]*result$displacement[d[1L]]+result$displacement[d[2L]]*result$displacement[d[2L]]),
    numeric(1)
)
result_summary <- function(a,kind,result) {
  entries <- magnitudes(a,result)
  node <- extreme_index(entries)
  energy <- ordered_total(vapply(seq_along(a$members),function(i) {
    n <- result$forces[i]
    p <- a$properties[[i]]
    n*n*a$geometry[[i]]$length/(2*p$young*p$area)
  },numeric(1)))/1000
  reactions <- vapply(
      seq_len(2L),
      function(axis) ordered_total(vapply(a$node_dofs,function(d) result$reactions[d[axis]],numeric(1)))/1000,
      numeric(1)
  )
  forces <- vapply(
      seq_len(2L),
      function(axis) ordered_total(vapply(a$node_dofs,function(d) result$external[d[axis]],numeric(1)))/1000,
      numeric(1)
  )
  scale <- max(1,max(abs(result$external)),max(abs(result$reactions)))
  equilibrium <- if (equilibrium_residual(result,a$geometry) <= 1e-6*scale) "ok" else "failed"
  words(
      kind,
      result$name,
      "equilibrium",
      equilibrium,
      "max_displacement",
      format_real(entries[node]),
      "at",
      a$nodes[[node]]$id,
      "energy",
      format_real(energy),
      "reactions",
      format_real(reactions[1L]),
      format_real(reactions[2L]),
      "loads",
      format_real(forces[1L]),
      format_real(forces[2L])
  )
}
deflection_report <- function(a) {
  settings <- a$settings$deflection
  name <- settings$name
  ratio <- settings$ratio
  result <- a$results[[name]]
  fixed <- vapply(Filter(function(d) d[2L] == 2L,a$support_directions),function(d) d[1L],integer(1))
  anchors <- which(a$deck %in% fixed)
  lines <- character()
  for (span in seq_len(length(anchors)-1L)) {
    first <- anchors[span]
    last <- anchors[span+1L]
    left <- a$deck[first]
    right <- a$deck[last]
    xa <- a$deck_x[first]
    xb <- a$deck_x[last]
    va <- result$displacement[a$node_dofs[[left]][2L]]
    vb <- result$displacement[a$node_dofs[[right]][2L]]
    interior <- seq.int(first+1L,last-1L)
    entries <- vapply(
        interior,
        function(i) abs(result$displacement[a$node_dofs[[a$deck[i]]][2L]]-(va+(vb-va)*(a$deck_x[i]-xa)/(xb-xa))),
        numeric(1)
    )
    chosen <- extreme_index(entries)
    largest <- entries[chosen]
    node <- a$deck[interior[chosen]]
    limit <- (xb-xa)/ratio
    lines <- c(
        lines,
        words(
            "deflection",
            name,
            "span",
            a$nodes[[left]]$id,
            a$nodes[[right]]$id,
            "max",
            format_real(largest),
            "at",
            a$nodes[[node]]$id,
            "limit",
            format_real(limit),
            if (largest <= limit) "ok" else "exceeded"
        )
    )
    unit <- unit_result(a,node)
    virtual <- ordered_total(vapply(
        seq_along(a$members),
        function(i) result$forces[i]*(unit$forces[i]/1000)*a$geometry[[i]]$length/(a$properties[[i]]$young*a$properties[[i]]$area),
        numeric(1)
    ))
    stiffness <- -result$displacement[a$node_dofs[[node]][2L]]
    verdict <- if (abs(virtual-stiffness) <= 1e-6*max(1,abs(stiffness))) "ok" else "failed"
    lines <- c(
        lines,
        words(
            "virtual_work",
            name,
            "node",
            a$nodes[[node]]$id,
            "stiffness",
            format_real(stiffness),
            "virtual",
            format_real(virtual),
            verdict
        )
    )
  }
  lines
}
removal_report <- function(a) {
  combination <- a$definitions[[a$settings$removal]]
  lines <- character()
  for (removed in seq_along(a$members)) {
    m <- a$members[[removed]]
    system <- build_system(a,a$choices,removed)
    if (system$unstable != 0L) {
      owner <- a$owners[[system$unstable]]
      lines <- c(lines,words("removal",m$id,"unstable at",a$nodes[[owner[1L]]]$id,c("x","y")[owner[2L]]))
      next
    }
    result <- analyze(a,system,combination)[[combination$name]]
    indices <- setdiff(seq_along(a$members),removed)
    entries <- vapply(
        indices,
        function(i) utilization(result$forces[i],system$properties[[i]],a$geometry[[i]]),
        numeric(1)
    )
    largest <- extreme_index(entries)
    displacements <- magnitudes(a,result)
    node <- extreme_index(displacements)
    lines <- c(
        lines,
        words(
            "removal",
            m$id,
            "stable max_utilization",
            format_real(entries[largest]),
            "at",
            a$members[[indices[largest]]]$id,
            "max_displacement",
            format_real(displacements[node]),
            "at",
            a$nodes[[node]]$id
        )
    )
  }
  lines
}
analysis_report <- function(a) {
  before <- numbering_metrics(seq_along(a$nodes)-1L,a$neighbors,a$members)
  after <- numbering_metrics(a$numbers,a$neighbors,a$members)
  ids <- vapply(a$nodes,function(n) n$id,integer(1))
  lines <- c(
      words(
          "model nodes",
          length(a$nodes),
          "members",
          length(a$members),
          "supports",
          length(a$model$supports),
          "free_dofs",
          length(a$free),
          "restrained_dofs",
          length(a$restrained),
          "indeterminacy",
          length(a$members)+length(a$restrained)-2L*length(a$nodes)
      ),
      paste("renumbering",paste(ids[a$order],collapse=" ")),
      words("bandwidth before",before[1L],"after",after[1L]),
      words("profile before",before[2L],"after",after[2L])
  )
  for (i in seq_along(a$members)) {
    m <- a$members[[i]]
    g <- a$geometry[[i]]
    lines <- c(
        lines,
        words(
            "member",
            m$id,
            "nodes",
            a$nodes[[m$start]]$id,
            a$nodes[[m$finish]]$id,
            "length",
            format_real(g$length),
            "cos",
            format_real(g$cosine,6L),
            "sin",
            format_real(g$sine,6L)
        )
    )
  }
  for (item in a$result_order) lines <- c(lines,result_summary(a,item$kind,a$results[[item$name]]))
  for (direction in a$support_directions) {
    node <- direction[1L]
    axis <- direction[2L]
    degree <- direction[3L]
    entries <- vapply(a$combinations,function(r) r$reactions[degree]/1000,numeric(1))
    hi <- extreme_index(entries)
    lo <- extreme_index(entries,TRUE)
    line <- words(
        "reaction_envelope",
        a$nodes[[node]]$id,
        c("x","y")[axis],
        "max",
        format_real(entries[hi]),
        a$combinations[[hi]]$name,
        "min",
        format_real(entries[lo]),
        a$combinations[[lo]]$name
    )
    if (axis == 2L) line <- paste(line,"uplift",if (any(entries < 0)) "yes" else "no")
    lines <- c(lines,line)
  }
  displacements <- lapply(a$combinations,function(r) magnitudes(a,r))
  for (node in seq_along(a$nodes)) {
    entries <- vapply(displacements,function(d) d[node],numeric(1))
    hi <- extreme_index(entries)
    lines <- c(
        lines,
        words(
            "displacement_envelope",
            a$nodes[[node]]$id,
            "max",
            format_real(entries[hi]),
            a$combinations[[hi]]$name
        )
    )
  }
  c(lines,deflection_report(a),removal_report(a))
}
ordinate <- function(a,entries,x) {
  if (x < a$deck_x[1L] || x > tail(a$deck_x,1L)) return(0)
  if (x == tail(a$deck_x,1L)) return(tail(entries,1L))
  i <- findInterval(x,a$deck_x)
  entries[i]+(entries[i+1L]-entries[i])*(x-a$deck_x[i])/(a$deck_x[i+1L]-a$deck_x[i])
}
vehicle_range <- function(a,entries,positions,axles) {
  effects <- vapply(
      positions,
      function(p) ordered_total(vapply(
          axles,
          function(axle) axle$load*ordinate(a,entries,p-axle$offset),
          numeric(1)
      )),
      numeric(1)
  )
  hi <- extreme_index(effects)
  lo <- extreme_index(effects,TRUE)
  list(largest=effects[hi],high_position=positions[hi],smallest=effects[lo],low_position=positions[lo])
}
influence_report <- function(a) {
  member_ordinates <- lapply(a$members,function(m) numeric())
  reaction_ordinates <- lapply(seq_len(a$degrees),function(d) numeric())
  for (node in a$deck) {
    result <- unit_result(a,node)
    for (i in seq_along(a$members)) member_ordinates[[i]] <- c(member_ordinates[[i]],result$forces[i]/1000)
    for (direction in a$support_directions) {
      d <- direction[3L]
      reaction_ordinates[[d]] <- c(reaction_ordinates[[d]],result$reactions[d]/1000)
    }
  }
  lines <- character()
  for (i in a$settings$influence) {
    entries <- member_ordinates[[i]]
    lines <- c(lines,words("influence",a$members[[i]]$id))
    for (k in seq_along(a$deck)) lines <- c(
        lines,
        words("node",a$nodes[[a$deck[k]]]$id,format_real(entries[k]))
    )
    hi <- extreme_index(entries)
    lo <- extreme_index(entries,TRUE)
    lines <- c(
        lines,
        words(
            "max",
            format_real(entries[hi]),
            "at",
            a$nodes[[a$deck[hi]]]$id,
            "min",
            format_real(entries[lo]),
            "at",
            a$nodes[[a$deck[lo]]]$id,
            "positive",
            format_real(ordered_total(entries[entries > 0])),
            "negative",
            format_real(ordered_total(entries[entries < 0]))
        )
    )
    crossings <- numeric()
    for (k in seq_len(length(entries)-1L)) {
      left <- entries[k]
      right <- entries[k+1L]
      if ((left > 0 && right < 0) || (left < 0 && right > 0)) crossings <- c(
          crossings,
          a$deck_x[k]+(a$deck_x[k+1L]-a$deck_x[k])*left/(left-right)
      )
    }
    line <- words("crossings",length(crossings))
    if (length(crossings)) line <- paste(line,paste(format_real(crossings,1L),collapse=" "))
    lines <- c(lines,line)
  }
  vehicle <- a$settings$vehicle
  axles <- vehicle$axles
  positions <- seq.int(a$deck_x[1L],tail(a$deck_x,1L)+tail(axles,1L)[[1L]]$offset,vehicle$step)
  lines <- c(lines,words("vehicle axles",length(axles),"positions",length(positions)))
  ranges <- list()
  for (i in seq_along(a$members)) {
    r <- vehicle_range(a,member_ordinates[[i]],positions,axles)
    ranges[[i]] <- r
    lines <- c(
        lines,
        words(
            "vehicle_member",
            a$members[[i]]$id,
            "max",
            format_real(r$largest),
            "at",
            r$high_position,
            "min",
            format_real(r$smallest),
            "at",
            r$low_position
        )
    )
  }
  for (direction in a$support_directions) {
    r <- vehicle_range(a,reaction_ordinates[[direction[3L]]],positions,axles)
    lines <- c(
        lines,
        words(
            "vehicle_reaction",
            a$nodes[[direction[1L]]]$id,
            c("x","y")[direction[2L]],
            "max",
            format_real(r$largest),
            "at",
            r$high_position,
            "min",
            format_real(r$smallest),
            "at",
            r$low_position
        )
    )
  }
  setting <- a$settings$rating
  dead <- a$results[[setting$name]]
  ratings <- list()
  for (i in seq_along(a$members)) {
    p <- a$properties[[i]]
    g <- a$geometry[[i]]
    r <- ranges[[i]]
    nd <- dead$forces[i]/1000
    pt <- p$area*p$yield_stress/1000
    pc <- min(p$area*p$yield_stress,buckling(p,g))/1000
    tension <- compression <- "none"
    if (rounded(r$largest) > 0) {
      rating <- (pt-setting$dead*nd)/(setting$vehicle*r$largest)
      tension <- format_real(rating)
      ratings[[length(ratings)+1L]] <- list(member=i,kind="tension",value=rating)
    }
    if (rounded(r$smallest) < 0) {
      rating <- (pc+setting$dead*nd)/(setting$vehicle*(-r$smallest))
      compression <- format_real(rating)
      ratings[[length(ratings)+1L]] <- list(member=i,kind="compression",value=rating)
    }
    lines <- c(lines,words("rating",a$members[[i]]$id,"tension",tension,"compression",compression))
  }
  selected <- ratings[[extreme_index(vapply(ratings,function(r) r$value,numeric(1)),TRUE)]]
  c(lines,words("rating_min",format_real(selected$value),"at",a$members[[selected$member]]$id,selected$kind))
}
vibration_report <- function(a) {
  setting <- a$settings$vibration
  external <- a$results[[setting$name]]$external
  masses <- vapply(a$node_dofs,function(d) -external[d[2L]]/9.81,numeric(1))
  free_masses <- vapply(a$free,function(d) masses[a$owners[[d]][1L]],numeric(1))
  n <- length(a$free)
  modes <- list()
  lines <- words(
      "vibration",
      setting$name,
      "mass",
      format_real(ordered_total(masses)),
      "iterations",
      setting$iterations
  )
  for (mode in seq_len(setting$modes)) {
    vector <- rep(1,n)
    for (iteration in seq_len(setting$iterations)) {
      for (previous in modes) {
        beta <- ordered_total(previous*free_masses*vector)
        vector <- vector-beta*previous
      }
      solution <- solve_cholesky(a$final_system$lower,free_masses*vector)
      magnitude <- sqrt(ordered_total(free_masses*solution*solution))
      vector <- solution/magnitude
    }
    modes[[length(modes)+1L]] <- vector
    product <- vapply(seq_len(n),function(i) ordered_total(a$final_system$free_matrix[i,]*vector),numeric(1))
    eigenvalue <- ordered_total(vector*product)/ordered_total(free_masses*vector*vector)
    frequency <- sqrt(1000*eigenvalue)/(2*TRUSS_PI)
    lines <- c(lines,words("mode",mode,"frequency",format_real(frequency),"period",format_real(1/frequency)))
    peak <- which.max(abs(vector))
    normalized <- numeric(a$degrees)
    normalized[a$free] <- vector/vector[peak]
    for (i in seq_along(a$nodes)) {
      d <- a$node_dofs[[i]]
      lines <- c(
          lines,
          words("node",a$nodes[[i]]$id,format_real(normalized[d[1L]]),format_real(normalized[d[2L]]))
      )
    }
  }
  lines
}
new_canvas <- function(nodes,horizontal,vertical) {
  canvas <- new.env(parent=emptyenv())
  x <- vapply(nodes,function(n) n$x,integer(1))
  y <- vapply(nodes,function(n) n$y,integer(1))
  canvas$x0 <- min(x)
  canvas$y1 <- max(y)
  canvas$horizontal <- horizontal
  canvas$vertical <- vertical
  canvas$width <- floor((max(x)-min(x))/horizontal+0.5)+5L
  canvas$height <- floor((max(y)-min(y))/vertical+0.5)+5L
  canvas$grid <- matrix(" ",canvas$height,canvas$width)
  canvas
}
canvas_position <- function(canvas,x,y) c(
    floor((x-canvas$x0)/canvas$horizontal+0.5)+2L,
    floor((canvas$y1-y)/canvas$vertical+0.5)+2L
)
canvas_put <- function(canvas,column,row,character) {
  if (column >= 0L && column < canvas$width && row >= 0L && row < canvas$height) canvas$grid[
      row+1L,
      column+1L
  ] <- character
}
draw_line <- function(canvas,first,last,character) {
  column <- first[1L]
  row <- first[2L]
  c1 <- last[1L]
  r1 <- last[2L]
  dc <- abs(c1-column)
  dr <- -abs(r1-row)
  sc <- if (column < c1) 1L else -1L
  sr <- if (row < r1) 1L else -1L
  error <- dc+dr
  repeat {
    canvas_put(canvas,column,row,character)
    if (column == c1 && row == r1) break
    twice <- 2L*error
    if (twice >= dr) {
      error <- error+dr
      column <- column+sc
    }
    if (twice <= dc) {
      error <- error+dc
      row <- row+sr
    }
  }
}
framed <- function(canvas) {
  border <- paste0("+",strrep("-",canvas$width),"+")
  c(
      border,
      vapply(
          seq_len(canvas$height),
          function(r) paste0("|",paste(canvas$grid[r,],collapse=""),"|"),
          character(1)
      ),
      border
  )
}
drawing_report <- function(a) {
  lines <- character()
  for (setting in a$settings$drawing) {
    result <- a$results[[setting$name]]
    canvas <- new_canvas(a$nodes,setting$horizontal,setting$vertical)
    original <- lapply(a$nodes,function(n) canvas_position(canvas,n$x,n$y))
    deformed <- lapply(seq_along(a$nodes),function(i) {
      n <- a$nodes[[i]]
      d <- a$node_dofs[[i]]
      canvas_position(
          canvas,
          n$x+setting$magnification*result$displacement[d[1L]],
          n$y+setting$magnification*result$displacement[d[2L]]
      )
    })
    for (m in a$members) draw_line(canvas,original[[m$start]],original[[m$finish]],".")
    for (point in original) canvas_put(canvas,point[1L],point[2L],"+")
    for (m in a$members) draw_line(canvas,deformed[[m$start]],deformed[[m$finish]],"*")
    for (point in deformed) canvas_put(canvas,point[1L],point[2L],"o")
    lines <- c(
        lines,
        words(
            "drawing",
            setting$name,
            "magnification",
            setting$magnification,
            "columns",
            canvas$width,
            "rows",
            canvas$height
        ),
        framed(canvas)
    )
  }
  scale <- a$settings$utilization_map
  canvas <- new_canvas(a$nodes,scale[1L],scale[2L])
  points <- lapply(a$nodes,function(n) canvas_position(canvas,n$x,n$y))
  for (i in seq_along(a$members)) {
    m <- a$members[[i]]
    u <- a$governing[i]
    character <- if (u >= 1) "#" else as.character(floor(10*u))
    draw_line(canvas,points[[m$start]],points[[m$finish]],character)
  }
  for (point in points) canvas_put(canvas,point[1L],point[2L],"o")
  c(lines,words("utilization_map columns",canvas$width,"rows",canvas$height),framed(canvas))
}
csv_reports <- function(a) {
  displacements <- "case,node,dx,dy"
  forces <- "case,member,force,stress,utilization"
  reactions <- "case,node,rx,ry"
  for (item in a$result_order) {
    name <- item$name
    result <- a$results[[name]]
    for (i in seq_along(a$nodes)) {
      d <- a$node_dofs[[i]]
      displacements <- c(
          displacements,
          paste(
              name,
              a$nodes[[i]]$id,
              format_real(result$displacement[d[1L]]),
              format_real(result$displacement[d[2L]]),
              sep=","
          )
      )
    }
    for (i in seq_along(a$members)) {
      n <- result$forces[i]
      p <- a$properties[[i]]
      forces <- c(
          forces,
          paste(
              name,
              a$members[[i]]$id,
              format_real(n/1000),
              format_real(n/p$area),
              format_real(utilization(n,p,a$geometry[[i]])),
              sep=","
          )
      )
    }
    for (support in a$model$supports) {
      d <- a$node_dofs[[support$node]]
      reactions <- c(
          reactions,
          paste(
              name,
              a$nodes[[support$node]]$id,
              format_real(result$reactions[d[1L]]/1000),
              format_real(result$reactions[d[2L]]/1000),
              sep=","
          )
      )
    }
  }
  list(displacements=displacements,forces=forces,reactions=reactions)
}
main <- function() {
  a <- truss_context(read_model())
  history <- design_sections(a)
  csv <- csv_reports(a)
  outputs <- list(
      "analysis.txt"=analysis_report(a),
      "displacements.csv"=csv$displacements,
      "member_forces.csv"=csv$forces,
      "reactions.csv"=csv$reactions,
      "design.txt"=design_report(a,history),
      "influence.txt"=influence_report(a),
      "drawing.txt"=drawing_report(a),
      "vibration.txt"=vibration_report(a)
  )
  dir.create("output",showWarnings=FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]],paste0("output/",name),useBytes=TRUE)
}
main()
