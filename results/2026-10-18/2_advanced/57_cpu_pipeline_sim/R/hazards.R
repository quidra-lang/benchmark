dependencies <- function(instructions) {
  last_writer <- integer(32L)
  sources <- vector("list",length(instructions))
  for (i in seq_along(instructions)) {
    instruction <- instructions[[i]]
    current <- list()
    for (field in seq_len(2L)) {
      register <- c(instruction$rs1,instruction$rs2)[field]
      if (register > 0L) current[[length(current)+1L]] <- list(
          field=field,
          register=register,
          producer=last_writer[register+1L]
      )
    }
    sources[[i]] <- current
    if (instruction$rd > 0L) last_writer[instruction$rd+1L] <- i
  }
  sources
}
id_resolved <- function(
    instruction,
    variant
) (instruction$kind == "JUMP" && instruction$rs1 == -1L) || (instruction$kind %in% c(
    "BRANCH",
    "JUMP"
) && variant$stage == "ID")
ready_cycle <- function(instruction,producer,producer_time,variant) {
  if (!variant$forwarding) return(producer_time[5L]+1L)
  result <- if (producer$kind == "LOAD") producer_time[5L] else producer_time[4L]
  result+as.integer(id_resolved(instruction,variant))
}
forwarding_path <- function(instruction,producer_time,instruction_time,variant) {
  if (is.null(producer_time) || !variant$forwarding) return(1L)
  resolved <- id_resolved(instruction,variant)
  use_cycle <- instruction_time[3L]-as.integer(resolved)
  if (producer_time[4L] == use_cycle) return(2L)
  if (!resolved && producer_time[5L] == use_cycle) return(3L)
  1L
}
