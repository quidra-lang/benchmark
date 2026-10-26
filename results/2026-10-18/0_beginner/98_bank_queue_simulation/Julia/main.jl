using Printf

function main()
    state, arrival, total_wait, max_wait = 42, 0, 0, 0
    free_times = [0, 0]
    for customer = 1:20
        state = (state*48271)%2147483647
        arrival += state%5+1
        state = (state*48271)%2147483647
        service = state%7+2
        teller = argmin(free_times)
        start = max(arrival, free_times[teller])
        departure = start+service
        wait = start-arrival
        free_times[teller] = departure
        total_wait += wait
        max_wait = max(max_wait, wait)
        println(
            "customer $customer: arrive=$arrival start=$start end=$departure teller=$teller wait=$wait",
        )
    end
    @printf("average wait: %.2f\n", total_wait/20)
    println("max wait: ", max_wait)
    println("last departure: ", maximum(free_times))
end

main()
