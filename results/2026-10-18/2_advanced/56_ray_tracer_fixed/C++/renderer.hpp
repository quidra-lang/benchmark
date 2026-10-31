#ifndef RENDERER_HPP
#define RENDERER_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <functional>
#include <limits>
#include <memory>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
constexpr I scale = 4096;
using Vec = std::array<I, 3>;
using Color = std::array<I, 3>;
using Ids = std::vector<int>;
using Lines = std::vector<std::string>;
struct Bounds {
    Vec lo{}, hi{};
};
struct Material {
    std::string name;
    Color color{}, second{};
    I kd = 0, ks = 0, exponent = 1, kr = 0, kt = 0, ior = scale, checker_size = 0;
};
enum class ObjectKind { sphere, plane, box };
enum class LightKind { point, spot, sun, area };
struct Object {
    ObjectKind kind;
    char label;
    int material;
    Vec first{}, second{};
    I radius = 0;
};
struct Light {
    LightKind kind;
    Vec position{}, direction{}, u{}, v{};
    I outer = 0, inner = 0, intensity = 0;
    int divisions = 1;
};
struct Scene {
    Vec eye{}, forward{}, right{}, up{};
    I half_width = 0, half_height = 0, ambient = 0;
    Color background{}, fog_color{};
    bool fog = false;
    I fog_start = 0, fog_end = 0;
    std::vector<Material> materials;
    std::vector<Object> objects;
    std::vector<Light> lights;
};
struct Settings {
    int width, height, contrast, depth;
    I far, epsilon, pad;
};
struct Ray {
    Vec origin, direction;
};
struct Slab {
    I near, far;
    int near_axis, far_axis;
};
struct Candidate {
    I distance;
    bool entering = false;
    int axis = 0;
};
struct Weights {
    I reflection, refraction;
    std::optional<Vec> direction;
    bool total_internal = false;
};
I floor_div(I a, I b);
I mul(I a, I b);
I isqrt(I value);
Vec add(Vec a, Vec b);
Vec sub(Vec a, Vec b);
Vec negate(Vec value);
I dot(Vec a, Vec b);
Vec sc(Vec value, I weight);
I length(Vec value);
Vec norm(Vec value);
Scene load_scene();
std::optional<Slab> slab(Bounds bounds, Ray ray);
std::optional<Candidate> intersect(const Object &object, Ray ray, I epsilon);
Vec outward_normal(const Object &object, Ray ray, Vec point, const Candidate &hit);
Bounds bounds(const Object &object, I pad);
Color base_color(const Material &material, Vec point);
std::array<I, 2> phong(const Material &material, Vec normal, Vec light, Vec view, I effective);
Vec reflected(Vec direction, Vec normal);
Weights refracted(const Material &material, Vec direction, Vec normal, bool front);
Color mix(Color local, I local_weight, Color reflection, I reflected_weight, Color refraction,
          I refracted_weight);
const char *kind_name(ObjectKind kind);
const char *kind_name(LightKind kind);
#endif
