#include <stdio.h>
#include <string.h>

const char *small[] = {"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
    "nineteen"}, *tens[] = {"", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty",
    "ninety"};
void under(int n, char *out) {
    out[0] = 0;
    if (n >= 100) {
        strcat(out, small[n / 100]);
        strcat(out, " hundred");
        n %= 100;
        if (n)
            strcat(out, " ");
    }
    if (n >= 20) {
        strcat(out, tens[n / 10]);
        if (n % 10) {
            strcat(out, "-");
            strcat(out, small[n % 10]);
        }
    } else if (n)
        strcat(out, small[n]);
}

int main(void) {
    int values[] = {0, 13, 40, 100, 568, 71000, 300019, 999999};
    for (int i = 0; i < 8; i++) {
        int n = values[i];
        char result[256] = "", part[128];
        if (n == 0)
            strcpy(result, "zero");
        if (n >= 1000) {
            under(n / 1000, part);
            strcat(result, part);
            strcat(result, " thousand");
        }
        if (n % 1000) {
            if (result[0])
                strcat(result, " ");
            under(n % 1000, part);
            strcat(result, part);
        }
        printf("%d: %s\n", n, result);
    }
    return 0;
}
