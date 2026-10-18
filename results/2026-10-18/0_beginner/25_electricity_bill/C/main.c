#include <stdio.h>

int main(void) {
    const char *names[] = {"Sato", "Suzuki", "Takahashi", "Tanaka", "Ito", "Watanabe"};
    int usage[] = {85, 120, 254, 300, 438, 176}, total = 0;
    for (int i = 0; i < 6; i++) {
        int u = usage[i], bill = 900;
        bill += (u < 120 ? u: 120) * 30;
        if (u > 120)
            bill += (u < 300 ? u - 120: 180) * 36;
        if (u > 300)
            bill += (u - 300) * 40;
        total += bill;
        printf("%s: %d kWh, %d yen\n", names[i], u, bill);
    }
    printf("total: %d yen\n", total);
    return 0;
}
