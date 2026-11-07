#include <stdio.h>

int main(void) {
    int factorial = 1;
    for (int n = 0; n <= 12; ++n) {
        if (n > 0) factorial *= n;
        printf("%d! = %d\n", n, factorial);
    }
    return 0;
}
