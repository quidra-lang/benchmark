for (module in c("mesh","materials","transient","steady","report")) source(paste0(module,".R"))
SOLVER_ORDER <- c("jacobi","gauss_seidel","sor","sor_estimated")
MILESTONE_FACTORS <- c(1000L,100L,10L,1L)
read_boundary <- function(plate) {
  segments <- sources <- list()
  for (line in readLines(file.path("input","boundary.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    if (words[1L] == "segment") {
      name <- words[2L]
      edge <- words[3L]
      kind <- words[6L]
      values <- as.numeric(words[-seq_len(6L)])
      theta <- if (kind == "fixed") values[1L] else if (kind == "convective") values[2L] else NULL
      coefficient <- if (kind == "convective") values[1L] else NULL
      segments[[length(segments)+1L]] <- list(name=name,edge=edge,kind=kind,theta=theta,coefficient=coefficient,
        faces=segment_faces(plate,edge,as.integer(words[4L]),as.integer(words[5L])))
    } else {
      bounds <- as.integer(words[3:6])
      cells <- source_cells(plate,bounds[1L],bounds[2L],bounds[3L],bounds[4L])
      power <- as.numeric(words[7L])
      times <- as.integer(words[-seq_len(7L)])
      intervals <- lapply(seq.int(1L,length(times),by=2L),function(i) times[c(i,i+1L)])
      sources[[length(sources)+1L]] <- list(
          name=words[2L],
          cells=cells,
          power=power,
          intervals=intervals,
          weight=power/length(cells)
      )
    }
  }
  list(segments=segments,sources=sources)
}
read_parameters <- function(plate) {
  params <- list(probes=list(),runs=list())
  for (line in readLines(file.path("input","params.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- words[1L]
    values <- words[-1L]
    if (key %in% c("end_time","probe_every","max_iterations")) params[[key]] <- as.integer(values[1L]) else if (key %in% c(
        "initial",
        "tolerance",
        "omega",
        "alarm",
        "limit"
    ))
      params[[key]] <- as.numeric(values[1L]) else if (key == "snapshots") params[[key]] <- as.integer(values) else if (key == "bands")
      params[[key]] <- as.numeric(values) else if (key == "probe") params$probes[[length(params$probes)+1L]] <- list(
          name=values[1L],
          point=cell(plate,as.integer(values[2L]),as.integer(values[3L]))
      ) else if (key == "run") {
      step <- as.integer(values[3L])
      params$runs[[length(params$runs)+1L]] <- list(name=values[1L],method=values[2L],step=step,dt=step/1000)
    } else params[[key]] <- values[1L]
  }
  params
}
operating <- function(source,time) any(vapply(
    source$intervals,
    function(interval) interval[1L] <= time && time < interval[2L],
    logical(1)
))
duty_ratio <- function(source,end_time) sum(vapply(
    source$intervals,
    function(interval) min(interval[2L],end_time)-min(interval[1L],end_time),
    integer(1)
))/end_time
source_terms <- function(sources,n,time=NULL) {
  field <- numeric(n)
  total <- 0
  for (source in sources) {
    if (!is.null(time) && !operating(source,time)) next
    total <- total+source$power
    for (p in source$cells) field[p] <- field[p]+source$weight
  }
  list(field=field,power=total)
}
build_system <- function(plate,materials,segments,sources) {
  codes <- vapply(materials,function(material) material$code,character(1))
  cell_material <- match(plate$codes,codes)
  material_cells <- lapply(seq_along(materials),function(i) which(cell_material == i))
  cell_materials <- materials[cell_material]
  capacity <- vapply(
      cell_materials,
      function(material) heat_capacity(material,plate$dx,plate$thickness),
      numeric(1)
  )
  faces <- lapply(seq_len(plate$count),function(p) lapply(plate$neighbors[p,],function(neighbor) {
    conductance <- if (neighbor == 0L) 0 else interior_conductance(
        cell_materials[[p]]$k,
        cell_materials[[neighbor]]$k,
        plate$thickness
    )
    list(neighbor=neighbor,g=conductance,theta=NULL)
  }))
  for (segment in segments) for (pair in segment$faces) {
    p <- pair[1L]
    direction <- pair[2L]
    face <- faces[[p]][[direction]]
    if (segment$kind == "fixed") face$g <- fixed_conductance(
        cell_materials[[p]]$k,
        plate$thickness
    ) else if (segment$kind == "convective")
      face$g <- convective_conductance(cell_materials[[p]]$k,segment$coefficient,plate$dx,plate$thickness)
    face$theta <- segment$theta
    faces[[p]][[direction]] <- face
  }
  diagonal <- vapply(faces,function(row) ordered_sum(vapply(row,function(face) face$g,numeric(1))),numeric(1))
  beta <- vapply(
      faces,
      function(row) ordered_sum(vapply(
          Filter(function(face) !is.null(face$theta),row),
          function(face) face$g*face$theta,
          numeric(1)
      )),
      numeric(1)
  )
  source <- source_terms(sources,plate$count)
  list(mesh=plate,materials=materials,segments=segments,sources=sources,cell_material=cell_material,material_cells=material_cells,capacity=capacity,
    faces=faces,diagonal=diagonal,beta=beta,source_all=source$field,total_power=source$power,dt_max=min(capacity/diagonal))
}
run_status <- function(run,system,params) {
  times <- c(params$end_time,params$probe_every,params$snapshots)
  for (source in system$sources) for (interval in source$intervals) times <- c(times,interval)
  if (any(times %% run$step != 0L)) return("step")
  if (run$method == "ftcs" && run$dt > system$dt_max) "unstable" else "accepted"
}
cell_text <- function(plate,p) paste(coordinates(plate,p),collapse=" ")
field_summary <- function(prefix,plate,field) {
  hottest <- which.max(field)
  paste(
      prefix,
      "max",
      real_text(field[hottest],2L),
      "at",
      cell_text(plate,hottest),
      "min",
      real_text(min(field),2L),
      "mean",
      real_text(ordered_sum(field)/plate$count,2L)
  )
}
stored_heat <- function(
    system,
    field,
    initial,
    cells=seq_len(system$mesh$count)
) ordered_sum(system$capacity[cells]*(field[cells]-initial))
segment_flow <- function(system,segment,field) {
  if (segment$kind == "insulated") return(0)
  ordered_sum(vapply(segment$faces,function(pair) {
    p <- pair[1L]
    face <- system$faces[[p]][[pair[2L]]]
    face$g*(face$theta-field[p])
  },numeric(1)))
}
step_boundary_energy <- function(system,segment,run,previous,updated,intermediate) {
  if (segment$kind == "insulated") return(0)
  terms <- vapply(segment$faces,function(pair) {
    p <- pair[1L]
    face <- system$faces[[p]][[pair[2L]]]
    temperature <- if (run$method == "ftcs") previous[p] else if (segment$edge %in% c(
        "left",
        "right"
    )) intermediate[p] else if (run$method == "backward_euler") updated[p] else (previous[p]+updated[p])/2
    face$g*(face$theta-temperature)
  },numeric(1))
  run$dt*ordered_sum(terms)
}
new_result <- function(run,status) {
  result <- new.env(parent=emptyenv())
  result$run <- run
  result$status <- status
  result$snapshots <- result$probe_samples <- list()
  result$segment_energy <- numeric()
  result$generated <- 0
  result$peak <- result$alarm <- NULL
  result$above <- result$steps <- 0L
  result$final <- numeric()
  result$stored <- result$boundary <- 0
  result$balance <- FALSE
  result
}
observe <- function(result,system,params,time,field) {
  hottest <- which.max(field)
  temperature <- field[hottest]
  if (is.null(result$peak) || temperature > result$peak$temperature) result$peak <- list(
      temperature=temperature,
      time=time,
      cell=hottest
  )
  if (temperature >= params$alarm) {
    if (is.null(result$alarm)) result$alarm <- list(time=time,cell=hottest)
    if (time > 0L) result$above <- result$above+result$run$step
  }
  if (time %% params$probe_every == 0L) result$probe_samples[[length(result$probe_samples)+1L]] <- list(
      time=time,
      temperatures=vapply(params$probes,function(probe) field[probe$point],numeric(1))
  )
  if (time %in% params$snapshots) result$snapshots[[as.character(time)]] <- list(
      field=field,
      stored=stored_heat(system,field,params$initial),
      boundary=ordered_sum(result$segment_energy),
      source=result$generated
  )
}
simulate_run <- function(run,system,params) {
  result <- new_result(run,"accepted")
  result$steps <- params$end_time %/% run$step
  result$segment_energy <- numeric(length(system$segments))
  field <- rep(params$initial,system$mesh$count)
  observe(result,system,params,0L,field)
  for (step in seq_len(result$steps)-1L) {
    source <- source_terms(system$sources,system$mesh$count,step*run$step)
    updated <- advance_field(run$method,system,field,source$field,run$dt)
    for (j in seq_along(system$segments)) result$segment_energy[j] <- result$segment_energy[j]+step_boundary_energy(
        system,
        system$segments[[j]],
        run,
        field,
        updated$field,
        updated$intermediate
    )
    result$generated <- result$generated+run$dt*source$power
    field <- updated$field
    observe(result,system,params,(step+1L)*run$step,field)
  }
  result$final <- field
  result$stored <- stored_heat(system,field,params$initial)
  result$boundary <- ordered_sum(result$segment_energy)
  result$balance <- abs(result$stored-result$boundary-result$generated) <= 0.000001*(abs(result$stored)+abs(result$boundary)+abs(result$generated))
  result
}
solve_steady <- function(system) {
  rhs <- system$beta+system$source_all
  vectors <- list(rhs,system$beta)
  for (source in system$sources) {
    vector <- numeric(system$mesh$count)
    vector[source$cells] <- 1/length(source$cells)
    vectors[[length(vectors)+1L]] <- vector
  }
  fields <- band_solve(system,vectors)
  list(rhs=rhs,solution=fields[[1L]],base=fields[[2L]],responses=fields[-c(1L,2L)])
}
run_iterative_methods <- function(system,params,solution,rhs) {
  jacobi <- iterate_steady(system,params$initial,params$tolerance,params$max_iterations,"jacobi")
  n <- length(jacobi$changes)
  rho <- sqrt(jacobi$changes[n]/jacobi$changes[n-2L])
  omega_opt <- 2/(1+sqrt(1-rho*rho))
  results <- list(jacobi)
  for (method in SOLVER_ORDER[-1L]) {
    omega <- if (method == "sor_estimated") omega_opt else params$omega
    results[[length(results)+1L]] <- iterate_steady(
        system,
        params$initial,
        params$tolerance,
        params$max_iterations,
        method,
        omega
    )
  }
  enriched <- lapply(results,function(result) {
    result$milestones <- vapply(MILESTONE_FACTORS,function(factor) {
      indices <- which(result$changes < params$tolerance*factor)
      if (length(indices)) as.character(indices[1L]) else "never"
    },character(1))
    n <- length(result$changes)
    result$rate <- sqrt(result$changes[n]/result$changes[n-2L])
    result$error <- max(abs(result$field-solution))
    result$residual <- maximum_residual(system,result$field,rhs)
    result
  })
  list(results=enriched,rho=rho,omega_opt=omega_opt)
}
steady_state_lines <- function(system,params,solution,base,responses,iterative) {
  plate <- system$mesh
  lines <- c(field_summary("steady",plate,solution),temperature_lines(plate,solution))
  for (i in seq_along(system$materials)) {
    material <- system$materials[[i]]
    cells <- system$material_cells[[i]]
    temperatures <- solution[cells]
    lines <- c(
        lines,
        paste(
            "material",
            material$code,
            material$name,
            "cells",
            length(cells),
            "min",
            real_text(min(temperatures),2L),
            "max",
            real_text(max(temperatures),2L),
            "mean",
            real_text(ordered_sum(temperatures)/length(cells),2L)
        )
    )
  }
  duties <- vapply(system$sources,function(source) duty_ratio(source,params$end_time),numeric(1))
  for (i in seq_along(system$sources)) {
    source <- system$sources[[i]]
    temperatures <- solution[source$cells]
    lines <- c(
        lines,
        paste(
            "source",
            source$name,
            "power",
            real_text(source$power,4L),
            "duty",
            real_text(duties[i],4L),
            "mean",
            real_text(ordered_sum(temperatures)/length(source$cells),2L),
            "max",
            real_text(max(temperatures),2L)
        )
    )
  }
  for (source in system$sources) for (j in seq_along(responses)) {
    coefficient <- ordered_sum(responses[[j]][source$cells])/length(source$cells)
    lines <- c(lines,paste("influence",source$name,system$sources[[j]]$name,real_text(coefficient,4L)))
  }
  superposition <- duty <- base
  for (p in seq_len(plate$count)) for (i in seq_along(system$sources)) {
    source <- system$sources[[i]]
    response <- responses[[i]]
    superposition[p] <- superposition[p]+source$power*response[p]
    duty[p] <- duty[p]+(duties[i]*source$power)*response[p]
  }
  verdict <- function(value) if (value) "ok" else "failed"
  lines <- c(lines,paste("superposition",verdict(max(abs(superposition-solution)) <= 0.000001)))
  for (i in seq_along(system$sources)) for (segment in system$segments) {
    value <- if (segment$kind == "insulated") 0 else ordered_sum(vapply(
        segment$faces,
        function(pair) system$faces[[pair[1L]]][[pair[2L]]]$g*responses[[i]][pair[1L]],
        numeric(1)
    ))
    lines <- c(lines,paste("path",system$sources[[i]]$name,segment$name,real_text(value,4L)))
  }
  lines <- c(lines,field_summary("duty_steady",plate,duty))
  for (i in seq_along(system$sources)) {
    source <- system$sources[[i]]
    response <- responses[[i]]
    powers <- (params$limit-(solution-source$power*response))/response
    p <- which.min(powers)
    lines <- c(
        lines,
        paste("headroom",source$name,"max_power",real_text(powers[p],4L),"at",cell_text(plate,p))
    )
  }
  interfaces <- list()
  largest <- -1
  chosen <- c(0L,0L)
  for (p in seq_len(plate$count)) for (direction in c(RIGHT,BOTTOM)) {
    face <- system$faces[[p]][[direction]]
    q <- face$neighbor
    if (q == 0L) next
    gradient <- abs(solution[p]-solution[q])/plate$dx
    if (gradient > largest) {
      largest <- gradient
      chosen <- c(p,q)
    }
    first <- system$cell_material[p]
    second <- system$cell_material[q]
    if (first == second) next
    flow <- face$g*(solution[p]-solution[q])
    if (first > second) {
      temporary <- first
      first <- second
      second <- temporary
      flow <- -flow
    }
    key <- paste(first,second,sep=",")
    previous <- interfaces[[key]]
    if (is.null(previous)) previous <- list(first=first,second=second,count=0L,forward=0,backward=0)
    previous$count <- previous$count+1L
    if (flow > 0) previous$forward <- previous$forward+flow else if (flow < 0) previous$backward <- previous$backward+abs(flow)
    interfaces[[key]] <- previous
  }
  if (length(interfaces)) {
    ordered <- order(
        vapply(interfaces,function(value) value$first,integer(1)),
        vapply(interfaces,function(value) value$second,integer(1))
    )
    for (i in ordered) {
      result <- interfaces[[i]]
      lines <- c(
          lines,
          paste(
              "interface",
              system$materials[[result$first]]$code,
              system$materials[[result$second]]$code,
              "faces",
              result$count,
              "forward",
              real_text(result$forward,4L),
              "backward",
              real_text(result$backward,4L)
          )
      )
    }
  }
  flows <- numeric()
  for (segment in system$segments) {
    flow <- segment_flow(system,segment,solution)
    flows <- c(flows,flow)
    lines <- c(lines,paste("segment",segment$name,segment$edge,segment$kind,"flow",real_text(flow,4L)))
  }
  balanced <- abs(ordered_sum(flows)+system$total_power) <= 0.000001*(ordered_sum(abs(flows))+system$total_power)
  lines <- c(
      lines,
      paste("sources",real_text(system$total_power,4L)),
      paste("balance",verdict(balanced)),
      paste(
          "max_gradient",
          real_text(largest,2L),
          "between",
          cell_text(plate,chosen[1L]),
          "and",
          cell_text(plate,chosen[2L])
      )
  )
  for (result in iterative) {
    prefix <- paste("solver",result$method)
    if (result$method %in% c("sor","sor_estimated")) prefix <- paste(
        prefix,
        "omega",
        real_text(result$omega,4L)
    )
    lines <- c(
        lines,
        paste(
            prefix,
            "iterations",
            result$iterations,
            "converged",
            if (result$converged) "yes" else "no",
            "rate",
            real_text(result$rate,6L),
            "milestones",
            paste(result$milestones,collapse=" ")
        )
    )
  }
  lines
}
rejected_run_line <- function(result,maximum_step=NULL) {
  run <- result$run
  line <- paste("run",run$name,run$method,"dt",time_text(run$step),"rejected",result$status)
  if (result$status == "unstable" && !is.null(maximum_step)) line <- paste(
      line,
      "max_dt",
      real_text(maximum_step,4L)
  )
  line
}
snapshot_lines <- function(system,params,results) {
  lines <- character()
  for (result in results) {
    if (result$status != "accepted") {
      lines <- c(lines,rejected_run_line(result,system$dt_max))
      next
    }
    run <- result$run
    for (time in params$snapshots) {
      field <- result$snapshots[[as.character(time)]]$field
      prefix <- paste("run",run$name,run$method,"dt",time_text(run$step),"time",time_text(time))
      lines <- c(lines,field_summary(prefix,system$mesh,field),temperature_lines(system$mesh,field))
    }
  }
  lines
}
probe_lines <- function(params,results) {
  lines <- "run,time,probe,temperature"
  for (result in results) if (result$status == "accepted") for (sample in result$probe_samples) for (i in seq_along(params$probes))
    lines <- c(
        lines,
        paste(
            result$run$name,
            time_text(sample$time),
            params$probes[[i]]$name,
            real_text(sample$temperatures[i],3L),
            sep=","
        )
    )
  lines
}
comparison_lines <- function(system,params,results,reference,solution,rhs,iterative,rho,omega_opt) {
  lines <- paste("ftcs_max_dt",real_text(system$dt_max,4L))
  for (result in results) {
    if (result$status != "accepted") {
      lines <- c(lines,rejected_run_line(result))
      next
    }
    run <- result$run
    peak <- result$peak
    alarm <- if (is.null(result$alarm)) "never" else paste(
        time_text(result$alarm$time),
        "at",
        cell_text(system$mesh,result$alarm$cell)
    )
    lines <- c(lines,paste("run",run$name,run$method,"dt",time_text(run$step),"steps",result$steps,"peak",real_text(peak$temperature,2L),"time",time_text(peak$time),"at",cell_text(system$mesh,peak$cell),"alarm",alarm,"above",time_text(result$above)),
      paste(
          "energy",
          run$name,
          "stored",
          real_text(result$stored,2L),
          "boundary",
          real_text(result$boundary,2L),
          "source",
          real_text(result$generated,2L),
          "balance",
          if (result$balance) "ok" else "failed"
      ))
    for (time in params$snapshots) {
      snapshot <- result$snapshots[[as.character(time)]]
      lines <- c(
          lines,
          paste(
              "energy_at",
              run$name,
              "time",
              time_text(time),
              "stored",
              real_text(snapshot$stored,2L),
              "boundary",
              real_text(snapshot$boundary,2L),
              "source",
              real_text(snapshot$source,2L)
          )
      )
    }
    for (i in seq_along(system$materials)) {
      value <- stored_heat(system,result$final,params$initial,system$material_cells[[i]])
      lines <- c(lines,paste("energy_material",run$name,system$materials[[i]]$code,real_text(value,2L)))
    }
    for (i in seq_along(system$segments)) lines <- c(
        lines,
        paste("energy_segment",run$name,system$segments[[i]]$name,real_text(result$segment_energy[i],2L))
    )
    for (i in seq_along(params$probes)) {
      readings <- vapply(result$probe_samples,function(sample) sample$temperatures[i],numeric(1))
      high <- which.max(readings)
      low <- which.min(readings)
      lines <- c(lines,paste("probe_summary",run$name,params$probes[[i]]$name,"max",real_text(readings[high],3L),"time",time_text(result$probe_samples[[high]]$time),
        "min",real_text(readings[low],3L),"time",time_text(result$probe_samples[[low]]$time)))
    }
    if (run$name != reference$run$name) for (time in params$snapshots) {
      errors <- abs(result$snapshots[[as.character(time)]]$field-reference$snapshots[[as.character(time)]]$field)
      rms <- sqrt(ordered_sum(errors*errors)/system$mesh$count)
      lines <- c(
          lines,
          paste(
              "compare",
              run$name,
              reference$run$name,
              "time",
              time_text(time),
              "max_diff",
              real_text(max(errors),6L),
              "rms_diff",
              real_text(rms,6L)
          )
      )
    }
    lines <- c(lines,paste("final",run$name,"steady_max_diff",real_text(max(abs(result$final-solution)),6L)))
  }
  lines <- c(lines,paste("steady direct max_residual",real_text(maximum_residual(system,solution,rhs),6L)))
  for (result in iterative) lines <- c(
      lines,
      paste(
          "steady",
          result$method,
          "iterations",
          result$iterations,
          "max_diff",
          real_text(result$error,6L),
          "max_residual",
          real_text(result$residual,6L)
      )
  )
  c(
      lines,
      paste("jacobi_spectral_radius",real_text(rho,6L),"squared",real_text(rho*rho,6L)),
      paste("omega_estimated",real_text(omega_opt,4L))
  )
}
isotherm_output <- function(system,params,solution,reference) {
  mapped <- isotherm_lines(system$mesh,solution,params$bands)
  lines <- c(paste("isotherms steady counts",paste(mapped$counts,collapse=" ")),mapped$lines)
  for (time in params$snapshots) {
    mapped <- isotherm_lines(system$mesh,reference$snapshots[[as.character(time)]]$field,params$bands)
    lines <- c(
        lines,
        paste(
            "isotherms",
            reference$run$name,
            "time",
            time_text(time),
            "counts",
            paste(mapped$counts,collapse=" ")
        ),
        mapped$lines
    )
  }
  lines
}
main <- function() {
  plate <- read_plate()
  materials <- read_materials()
  boundary <- read_boundary(plate)
  params <- read_parameters(plate)
  system <- build_system(plate,materials,boundary$segments,boundary$sources)
  solved <- solve_steady(system)
  iterations <- run_iterative_methods(system,params,solved$solution,solved$rhs)
  results <- lapply(params$runs,function(run) {
    status <- run_status(run,system,params)
    if (status == "accepted") simulate_run(run,system,params) else new_result(run,status)
  })
  reference <- Filter(function(result) result$run$name == params$reference,results)[[1L]]
  outputs <- list("snapshots.txt"=snapshot_lines(system,params,results),"probes.csv"=probe_lines(params,results),
    "steady_state.txt"=steady_state_lines(
        system,
        params,
        solved$solution,
        solved$base,
        solved$responses,
        iterations$results
    ),
    "solver_comparison.txt"=comparison_lines(
        system,
        params,
        results,
        reference,
        solved$solution,
        solved$rhs,
        iterations$results,
        iterations$rho,
        iterations$omega_opt
    ),
    "isotherms.txt"=isotherm_output(system,params,solved$solution,reference))
  for (name in names(outputs)) write_lines(name,outputs[[name]])
}
main()
