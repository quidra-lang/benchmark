import 'dart:math' as math;

void main() {
    var state = 42, arrival = 0, totalWait = 0, maxWait = 0;
    final free = [0, 0];
    for (var customer = 1; customer <= 20; customer++) {
        state = (state * 48271) % 2147483647;
        arrival += state % 5 + 1;
        state = (state * 48271) % 2147483647;
        final service = state % 7 + 2, teller = free[0] <= free[1] ? 0 : 1, start = math.max(arrival,
            free[teller]), end = start + service, wait = start - arrival;
        free[teller] = end;
        totalWait += wait;
        maxWait = math.max(maxWait, wait);
        print('customer $customer: arrive=$arrival start=$start end=$end teller=${teller+1} wait=$wait');
    }
    print('average wait: ${(totalWait / 20).toStringAsFixed(2)}\nmax wait: $maxWait\nlast departure: ${math.max(free[0],free[1])}');
}
