#include <stdio.h>

int main(void) {
    const char *names[] = {"Aiko", "Kenji", "Mika", "Ryo", "Yuki"};
    int heights[] = {158, 172, 165, 180, 150}, weights[] = {45, 68, 70, 101, 52};
    for (int i = 0; i < 5; i++) {
        int numerator = weights[i] * 10000, denominator = heights[i] * heights[i];
        double bmi = (double)numerator / denominator;
        const char *category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";
        printf("%s: BMI %.1f (%s)\n", names[i], bmi, category);
    }
    return 0;
}
