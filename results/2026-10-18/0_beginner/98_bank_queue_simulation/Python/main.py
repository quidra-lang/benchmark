state = 42
arrival = 0
free_times = [0, 0]
waits = []
for customer in range(1, 21):
    state = state * 48271 % 2147483647
    arrival += state % 5 + 1
    state = state * 48271 % 2147483647
    service = state % 7 + 2
    teller = 0 if free_times[0] <= free_times[1] else 1
    start = max(arrival, free_times[teller])
    end = start + service
    free_times[teller] = end
    wait = start - arrival
    waits.append(wait)
    print(
        f"customer {customer}: arrive={arrival} start={start} end={end} "
        f"teller={teller + 1} wait={wait}"
    )
print(f"average wait: {sum(waits) / 20:.2f}")
print(f"max wait: {max(waits)}")
print(f"last departure: {max(free_times)}")
