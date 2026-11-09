#ifndef TRUSS_HPP
#define TRUSS_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
using Indices = std::vector<int>;
using Names = std::vector<std::string>;
using Lines = Names;
struct Node {
    int id, x, y;
};
struct Member {
    int id, start, end, section, material;
    std::string group;
};
struct Section {
    std::string name;
    double area, inertia;
};
struct Material {
    std::string name;
    double young, yield_stress, density, expansion;
};
struct Support {
    int node;
    std::array<bool, 2> fixed;
    std::array<double, 2> prescribed;
};
enum class LoadKind { Force, Temperature, Selfweight, Settlement };
struct Load {
    LoadKind kind;
    int index = -1;
    double x = 0, y = 0;
};
struct LoadCase {
    std::string name;
    std::vector<Load> lines;
};
struct Combination {
    std::string name;
    std::vector<std::pair<int, double>> terms;
};
struct Axle {
    int offset;
    double load;
};
struct Drawing {
    std::string name;
    int magnification, horizontal, vertical;
};
struct Settings {
    Indices deck, influence;
    int vehicle_step = 0;
    std::vector<Axle> axles;
    std::string rating, deflection, vibration, removal;
    double dead_factor = 0, vehicle_factor = 0, compression_limit = 0, tension_limit = 0;
    int deflection_ratio = 0, modes = 0, iterations = 0, map_horizontal = 0, map_vertical = 0;
    std::vector<Drawing> drawings;
};
struct Model {
    std::vector<Node> nodes;
    std::vector<Member> members;
    std::vector<Section> sections;
    std::vector<Material> materials;
    std::vector<Support> supports;
    std::vector<LoadCase> cases;
    std::vector<Combination> combinations;
    Settings settings;
};
Model read_model();
struct Geometry {
    double length, cosine, sine;
    std::array<int, 4> dofs;
};
struct Properties {
    double area, inertia, young, yield_stress, density, expansion, stiffness;
};
std::vector<Geometry> member_geometry(const Model &model,
                                      const std::vector<std::array<int, 2>> &dofs);
std::vector<Properties> member_properties(const Model &model, const Indices &choices,
                                          const std::vector<Geometry> &geometry);
double member_weight(const Properties &properties, const Geometry &geometry);
std::array<std::array<double, 4>, 4> member_stiffness(const Properties &properties,
                                                      const Geometry &geometry);
Matrix assemble(const std::vector<Geometry> &geometry, const std::vector<Properties> &properties,
                int degrees, int removed = -1);
struct Loading {
    Vector external, total, temperature;
    bool settlement = false;
};
Loading load_vectors(const LoadCase &load_case, const std::vector<Geometry> &geometry,
                     const std::vector<Properties> &properties,
                     const std::vector<std::array<int, 2>> &node_dofs, int degrees,
                     int removed = -1);
struct Cholesky {
    Matrix lower;
    std::optional<int> unstable;
};
Cholesky cholesky(const Matrix &matrix, const Indices &free);
Vector solve(const Matrix &lower, const Vector &right);
struct Result {
    std::string name;
    Vector displacement, forces, reactions, external;
};
Vector axial_forces(const std::vector<Geometry> &geometry,
                    const std::vector<Properties> &properties, const Vector &displacement,
                    const Vector &temperature, int removed = -1),
    reactions(const Matrix &matrix, const Vector &displacement, const Vector &force,
              const Indices &restrained);
Result superpose(const Combination &combination, const std::vector<Result> &cases);
double equilibrium_residual(const Result &result, const std::vector<Geometry> &geometry);
constexpr double pi = 3.141592653589793;
double buckling(const Properties &properties, const Geometry &geometry, double inertia),
    utilization(double force, const Properties &properties, const Geometry &geometry,
                const Section *section = nullptr),
    slenderness(const Properties &properties, const Geometry &geometry,
                const Section *section = nullptr),
    slenderness_limit(int number, const std::vector<Result> &combinations, double compression,
                      double tension);
int select_section(const Indices &members, const std::vector<Section> &sections,
                   const std::vector<Properties> &properties, const std::vector<Geometry> &geometry,
                   const std::vector<Result> &combinations, const Vector &limits);
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
#endif
