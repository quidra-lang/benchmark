btb <- function(entries) {
  table <- new.env(parent=emptyenv())
  table$tags <- rep(-1L,entries)
  table$targets <- integer(entries)
  table
}
lookup <- function(table,pc) {
  index <- (pc %/% 4L) %% length(table$tags)+1L
  if (table$tags[index] == pc) table$targets[index] else NULL
}
insert <- function(table,pc,target) {
  index <- (pc %/% 4L) %% length(table$tags)+1L
  table$tags[index] <- pc
  table$targets[index] <- target
}
ras <- function(depth) {
  result <- new.env(parent=emptyenv())
  result$depth <- depth
  result$stack <- integer()
  result
}
ras_push <- function(ras,address) {
  if (ras$depth == 0L) return(invisible(NULL))
  if (length(ras$stack) == ras$depth) ras$stack <- ras$stack[-1L]
  ras$stack <- c(ras$stack,address)
}
ras_pop <- function(ras) {
  if (!length(ras$stack)) return(NULL)
  value <- tail(ras$stack,1L)
  ras$stack <- head(ras$stack,-1L)
  value
}
updated <- function(counter,taken) if (taken) min(3L,counter+1L) else max(0L,counter-1L)
direction_predictor <- function(scheme,parameters) {
  result <- new.env(parent=emptyenv())
  result$scheme <- scheme
  result$parameters <- parameters
  result$history <- 0L
  if (scheme %in% c("ONEBIT","TWOBIT","GSHARE")) result$table <- rep(
      if (scheme == "ONEBIT") 0L else 1L,
      parameters[1L]
  )
  if (scheme == "TOURNAMENT") {
    result$local_table <- rep(1L,parameters[1L])
    result$global_table <- rep(1L,parameters[2L])
    result$chooser <- rep(1L,parameters[4L])
  }
  result
}
direction_prediction <- function(predictor,pc,target) {
  scheme <- predictor$scheme
  if (scheme %in% c("STATIC_NT","PERFECT")) return(FALSE)
  if (scheme == "BTFN") return(target < pc)
  if (scheme %in% c("ONEBIT","TWOBIT","GSHARE")) {
    key <- if (scheme == "GSHARE") bitwXor(pc %/% 4L,predictor$history) else pc %/% 4L
    index <- key %% length(predictor$table)+1L
    return(if (scheme == "ONEBIT") predictor$table[index] == 1L else predictor$table[index] >= 2L)
  }
  local <- predictor$local_table[(pc %/% 4L) %% length(predictor$local_table)+1L] >= 2L
  global <- predictor$global_table[bitwXor(
      pc %/% 4L,
      predictor$history
  ) %% length(predictor$global_table)+1L] >= 2L
  if (predictor$chooser[(pc %/% 4L) %% length(predictor$chooser)+1L] >= 2L) global else local
}
direction_update <- function(predictor,pc,taken) {
  scheme <- predictor$scheme
  if (scheme %in% c("STATIC_NT","BTFN","PERFECT")) return(invisible(NULL))
  if (scheme == "TOURNAMENT") {
    li <- (pc %/% 4L) %% length(predictor$local_table)+1L
    gi <- bitwXor(pc %/% 4L,predictor$history) %% length(predictor$global_table)+1L
    ci <- (pc %/% 4L) %% length(predictor$chooser)+1L
    lp <- predictor$local_table[li] >= 2L
    gp <- predictor$global_table[gi] >= 2L
    if (lp != gp) predictor$chooser[ci] <- updated(predictor$chooser[ci],gp == taken)
    predictor$local_table[li] <- updated(predictor$local_table[li],taken)
    predictor$global_table[gi] <- updated(predictor$global_table[gi],taken)
    predictor$history <- (2L*predictor$history+as.integer(taken)) %% bitwShiftL(1L,predictor$parameters[3L])
  } else {
    key <- if (scheme == "GSHARE") bitwXor(pc %/% 4L,predictor$history) else pc %/% 4L
    index <- key %% length(predictor$table)+1L
    predictor$table[index] <- if (scheme == "ONEBIT") as.integer(taken) else updated(
        predictor$table[index],
        taken
    )
    if (scheme == "GSHARE") predictor$history <- (2L*predictor$history+as.integer(taken)) %% bitwShiftL(
        1L,
        predictor$parameters[2L]
    )
  }
}
storage_bits <- function(predictor) {
  scheme <- predictor$scheme
  p <- predictor$parameters
  if (scheme %in% c("STATIC_NT","BTFN","PERFECT")) return(0L)
  if (scheme == "ONEBIT") return(p[1L])
  if (scheme == "TWOBIT") return(2L*p[1L])
  if (scheme == "GSHARE") return(2L*p[1L]+p[2L])
  2L*(p[1L]+p[2L]+p[4L])+p[3L]
}
