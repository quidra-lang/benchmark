read_inputs <- function() {
  rows <- strsplit(readLines(file.path("input","cases.csv"))[-1L],",",fixed=TRUE)
  cases <- vapply(rows,function(words) as.integer(words[2L]),integer(1))
  deaths <- vapply(rows,function(words) as.integer(words[3L]),integer(1))
  groups <- contacts <- list()
  for (line in readLines(file.path("input","population.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    if (words[1L] == "group") groups[[length(groups)+1L]] <- list(
        name=words[2L],
        population=as.integer(words[3L]),
        fatality=as.numeric(words[4L])
    ) else
      contacts[[length(contacts)+1L]] <- as.numeric(words[-1L])
  }
  interventions <- lapply(
      strsplit(readLines(file.path("input","interventions.txt"))," ",fixed=TRUE),
      function(words) list(day=as.integer(words[1L]),multiplier=as.numeric(words[2L]))
  )
  params <- list(scenario=list(),contact_change=list())
  for (line in readLines(file.path("input","params.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    name <- words[1L]
    values <- words[-1L]
    if (name == "scenario") params[[name]][[length(params[[name]])+1L]] <- list(
        name=values[1L],
        multiplier=as.numeric(values[2L])
    ) else if (name == "contact_change")
      params[[name]][[length(params[[name]])+1L]] <- list(
          name=values[1L],
          group=values[2L],
          factor=as.numeric(values[3L])
      ) else if (name %in% c("holdout","death_lag","generation","horizon"))
      params[[name]] <- as.integer(values[1L]) else if (name %in% c("milestones","golden")) params[[name]] <- as.integer(values) else if (name %in% c(
          "beta_grid",
          "rho_grid"
      ))
      params[[name]] <- list(
          as.numeric(values[1L]),
          as.numeric(values[2L]),
          as.integer(values[3L])
      ) else if (name == "nelder_mead")
      params[[name]] <- c(
          as.list(as.numeric(values[1:4])),
          list(as.integer(values[5L]))
      ) else if (name %in% c("initial","simplex")) params[[name]] <- as.numeric(values) else params[[name]] <- as.numeric(values[1L])
  }
  list(
      cases=cases,
      deaths=deaths,
      groups=groups,
      contacts=do.call(rbind,contacts),
      interventions=interventions,
      params=params
  )
}
write_outputs <- function(outputs) {
  dir.create("output",showWarnings=FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]],file.path("output",name),useBytes=TRUE)
}
