#include <stdio.h>

int main(void) {
    long long x = 42;
    int free_time[2] = {0}, arrival = 0, total_wait = 0, maximum = 0;
    for (int k = 1; k <= 20; k++) {
        x = x * 48271 % 2147483647;
        arrival += (int)(x % 5) + 1;
        x = x * 48271 % 2147483647;
        int service = (int)(x % 7) + 2;
        int teller = free_time[0] <= free_time[1] ? 0 : 1;
        int start = arrival > free_time[teller] ? arrival : free_time[teller];
        int end = start + service;
        int wait = start - arrival;
        free_time[teller] = end;
        total_wait += wait;
        if (wait > maximum)
            maximum = wait;
        printf("customer %d: arrive=%d start=%d end=%d teller=%d wait=%d\n", k, arrival, start, end, teller + 1,
            wait);
    }
    printf("average wait: %.2f\nmax wait: %d\nlast departure: %d\n", total_wait / 20.0, maximum,
        free_time[0] > free_time[1] ? free_time[0] : free_time[1]);
    return 0;
}
