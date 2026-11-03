seird <- function(population,sigma,fatality,beta,gamma) {
  force(population)
  force(sigma)
  force(fatality)
  force(beta)
  force(gamma)
  function(state,multiplier) {
    susceptible <- state[1L]
    exposed <- state[2L]
    infectious <- state[3L]
    flow <- beta*multiplier*susceptible*infectious/population
    progression <- sigma*exposed
    removal <- gamma*infectious
    c(
        -flow,
        flow-progression,
        progression-removal,
        (1-fatality)*gamma*infectious,
        fatality*gamma*infectious,
        progression
    )
  }
}
sir <- function(population,beta,gamma) {
  force(population)
  force(beta)
  force(gamma)
  function(state,multiplier) {
    susceptible <- state[1L]
    infectious <- state[2L]
    flow <- beta*multiplier*susceptible*infectious/population
    removal <- gamma*infectious
    c(-flow,flow-removal,removal,flow)
  }
}
age_seird <- function(populations,fatalities,sigma,beta,gamma,contacts) {
  force(populations)
  force(fatalities)
  force(sigma)
  force(beta)
  force(gamma)
  force(contacts)
  function(state,multiplier) {
    result <- numeric(6L*length(populations))
    for (g in seq_along(populations)) {
      start <- 6L*(g-1L)
      susceptible <- state[start+1L]
      exposed <- state[start+2L]
      infectious <- state[start+3L]
      pressure <- 0
      for (h in seq_along(populations)) pressure <- pressure+contacts[g,h]*state[6L*(h-1L)+3L]/populations[h]
      force <- beta*multiplier*pressure
      flow <- force*susceptible
      progression <- sigma*exposed
      removal <- gamma*infectious
      result[seq.int(start+1L,start+6L)] <- c(
          -flow,
          flow-progression,
          progression-removal,
          (1-fatalities[g])*gamma*infectious,
          fatalities[g]*gamma*infectious,
          progression
      )
    }
    result
  }
}
generation <- function(sigma,gamma) {
  force(sigma)
  force(gamma)
  function(state,multiplier) {
    progression <- sigma*state[1L]
    removal <- gamma*state[2L]
    c(-progression,progression-removal,removal)
  }
}
