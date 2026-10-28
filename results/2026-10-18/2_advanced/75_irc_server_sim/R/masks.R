mask_matches <- function(mask,value) {
  mask <- strsplit(irc_fold(mask),"",fixed=TRUE)[[1L]]
  value <- strsplit(irc_fold(value),"",fixed=TRUE)[[1L]]
  pattern <- position <- restart <- 1L
  star <- 0L
  while (position <= length(value)) {
    if (pattern <= length(mask) && mask[pattern] == "*") {
      star <- pattern
      pattern <- pattern+1L
      restart <- position
    } else if (pattern <= length(mask) && (mask[pattern] == "?" || mask[pattern] == value[position])) {
      pattern <- pattern+1L
      position <- position+1L
    } else if (star != 0L) {
      restart <- restart+1L
      position <- restart
      pattern <- star+1L
    } else return(FALSE)
  }
  while (pattern <= length(mask) && mask[pattern] == "*") pattern <- pattern+1L
  pattern == length(mask)+1L
}
normalize_mask <- function(argument) {
  has_bang <- grepl("!",argument,fixed=TRUE)
  has_at <- grepl("@",argument,fixed=TRUE)
  if (has_bang && has_at) return(argument)
  if (has_at) return(paste0("*!",argument))
  if (has_bang) return(paste0(argument,"@*"))
  if (grepl(".",argument,fixed=TRUE)) return(paste0("*!*@",argument))
  paste0(argument,"!*@*")
}
