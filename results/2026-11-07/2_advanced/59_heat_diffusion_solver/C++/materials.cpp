#include "heat.hpp"
std::vector<Material> read_materials() {
    std::ifstream input("input/materials.txt");
    std::vector<Material> out;
    Material material;
    while (input >> material.code >> material.name >> material.k >> material.rho >> material.cp)
        out.push_back(material);
    return out;
}
double capacity(const Material &material, double dx, double thickness) {
    return material.rho * material.cp * dx * dx * thickness;
}
double interior(double first, double second, double thickness) {
    return 2 * first * second / (first + second) * thickness;
}
double fixed(double conductivity, double thickness) { return 2 * conductivity * thickness; }
double convective(double conductivity, double coefficient, double dx, double thickness) {
    return 1 / (1 / (coefficient * dx * thickness) + 1 / (2 * conductivity * thickness));
}
