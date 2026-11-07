new_net <- function(places,transitions,arcs,initial,final) {
  transitions <- sort(transitions)
  inputs <- setNames(
      lapply(transitions,function(t) which(vapply(places,function(p) pair_key(p,t) %in% arcs,logical(1)))),
      transitions
  )
  outputs <- setNames(
      lapply(transitions,function(t) which(vapply(places,function(p) pair_key(t,p) %in% arcs,logical(1)))),
      transitions
  )
  routes <- lapply(
      places,
      function(p) transitions[vapply(transitions,function(t) pair_key(p,t) %in% arcs,logical(1))]
  )
  first <- match(initial,places)
  last <- match(final,places)
  list(
      places=places,
      transitions=transitions,
      arcs=unique(arcs),
      initial=first,
      final=last,
      inputs=inputs,
      outputs=outputs,
      routes=routes,
      initial_marking=as.integer(seq_along(places) == first),
      final_marking=as.integer(seq_along(places) == last)
  )
}
enabled <- function(net,marking,t) all(marking[net$inputs[[t]]] >= 1L)
enabled_transitions <- function(net,marking) net$transitions[vapply(
    net$transitions,
    function(t) enabled(net,marking,t),
    logical(1)
)]
fire <- function(net,marking,t) {
  marking[net$inputs[[t]]] <- marking[net$inputs[[t]]]-1L
  marking[net$outputs[[t]]] <- marking[net$outputs[[t]]]+1L
  marking
}
read_model <- function() {
  places <- transitions <- arcs <- character()
  initial <- final <- ""
  for (line in readLines("input/model.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    if (words[1L] == "PLACE") places <- c(places,words[2L]) else if (words[1L] == "TRANSITION") transitions <- c(transitions,words[2L]) else if (words[1L] == "ARC") arcs <- c(
        arcs,
        pair_key(words[2L],words[3L])
    ) else if (words[1L] == "INITIAL") initial <- words[2L] else final <- words[2L]
  }
  new_net(places,transitions,arcs,initial,final)
}
new_replay_totals <- function(n) list2env(
    list(
        missing=0,
        remaining=0,
        consumed=0,
        produced=0,
        skipped=0,
        place_missing=numeric(n),
        place_remaining=numeric(n),
        deviating=numeric(n),
        waiting=lapply(seq_len(n),function(unused) numeric()),
        routes=lapply(seq_len(n),function(unused) numeric())
    ),
    parent=emptyenv()
)
fitness <- function(r) q(
    2*r$consumed*r$produced-r$missing*r$produced-r$remaining*r$consumed,
    2*r$consumed*r$produced
)
