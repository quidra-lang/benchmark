priority_order <- function(first,second,a,b) {
  da <- first$departure+first$delay
  db <- second$departure+second$delay
  if (da > db || (da == db && a > b)) c(a,b) else c(b,a)
}
manoeuvres <- function(max_delay) c(
    list(
        list(name="level_up",amount=10L),
        list(name="level_down",amount=-10L),
        list(name="speed_down",amount=0L)
    ),
    lapply(seq.int(60L,max_delay,60L),function(delay) list(name=paste0("delay_",delay),amount=delay))
)
propose <- function(plan,name,amount,types,params) {
  changed <- plan
  if (name %in% c("level_up","level_down")) {
    changed$offset <- changed$offset+amount
    levels <- level_list(changed)
    if (any(levels < params$level_min | levels > params$level_max)) return(NULL)
  } else if (name == "speed_down") {
    changed$speed <- as.integer((changed$speed*9L) %/% 10L)
    if (changed$speed < types[[changed$type]]$minimum) return(NULL)
  } else changed$delay <- changed$delay+amount
  changed
}
