#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    const char *names[] = {"Nina", "Leo", "Emma"}, *transactions[] = {"deposit Emma 1200", "withdraw Leo 4000",
        "transfer Nina Leo 5000", "withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",
        "withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800"};
    int balances[] = {12000, 3500, 800};
    for (int k = 0; k < 10; k++) {
        char op[16], from[16], to[16];
        int amount;
        sscanf(transactions[k], "%15s %15s %15s %d", op, from, to, &amount);
        if (strcmp(op, "transfer") != 0) amount = atoi(to);
        int a = 0, b = 0;
        while (strcmp(names[a], from))
            a++;
        if (strcmp(op, "transfer") == 0) {
            while (strcmp(names[b], to))
                b++;
        }
        int ok = strcmp(op, "deposit") == 0 || balances[a] >= amount;
        if (ok) {
            if (strcmp(op, "deposit") == 0)
                balances[a] += amount;
            else {
                balances[a] -= amount;
                if (strcmp(op, "transfer") == 0)
                    balances[b] += amount;
            }
        }
        printf("op %d: %s %s\n", k + 1, transactions[k], ok ? "ok": "failed (insufficient funds)");
    }
    int order[] = {0, 1, 2};
    for (int i = 0; i < 3; i++)
        for (int j = i + 1; j < 3; j++)
            if (strcmp(names[order[i]], names[order[j]]) > 0) {
                int t = order[i];
                order[i] = order[j];
                order[j] = t;
            }
    for (int i = 0; i < 3; i++)
        printf("%s: %d\n", names[order[i]], balances[order[i]]);
    return 0;
}
