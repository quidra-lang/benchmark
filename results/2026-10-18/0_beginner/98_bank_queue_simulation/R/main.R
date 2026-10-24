state <- 42
arrival <- 0
total_wait <- 0
max_wait <- 0
free_times <- c(0,0)
for (customer in 1:20) {
    state <- (state*48271) %% 2147483647
    arrival <- arrival+state %% 5+1
    state <- (state*48271) %% 2147483647
    service <- state %% 7+2
    teller <- which.min(free_times)
    start <- max(arrival,free_times[teller])
    departure <- start+service
    wait <- start-arrival
    free_times[teller] <- departure
    total_wait <- total_wait+wait
    max_wait <- max(max_wait,wait)
    cat(sprintf("customer %d: arrive=%d start=%d end=%d teller=%d wait=%d\n",customer,arrival,start,departure,teller,wait))
}
cat(sprintf("average wait: %.2f\nmax wait: %d\nlast departure: %d\n",total_wait/20,max_wait,max(free_times)))
