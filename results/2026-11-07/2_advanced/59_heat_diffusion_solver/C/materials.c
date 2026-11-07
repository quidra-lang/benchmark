#include "heat.h"
int read_materials(Material *materials) {
    FILE *input = fopen("input/materials.txt", "r");
    int count = 0;
    Material value;
    while (fscanf(input, " %c %16s %lf %lf %lf", &value.code, value.name, &value.k, &value.rho,
                  &value.cp) == 5)
        materials[count++] = value;
    fclose(input);
    return count;
}
double capacity(Material material, double dx, double thickness) {
    return material.rho * material.cp * dx * dx * thickness;
}
double interior(double first, double second, double thickness) {
    return 2 * first * second / (first + second) * thickness;
}
double fixed(double conductivity, double thickness) { return 2 * conductivity * thickness; }
double convective(double conductivity, double coefficient, double dx, double thickness) {
    return 1 / (1 / (coefficient * dx * thickness) + 1 / (2 * conductivity * thickness));
}
