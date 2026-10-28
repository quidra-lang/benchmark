#ifndef RENDERER_H
#define RENDERER_H
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <stdarg.h>
#include <limits.h>
#include <sys/stat.h>
typedef int64_t I;
enum { SCALE = 4096 };
typedef struct {
    I data[3];
} Vec;
typedef Vec Color;
typedef struct {
    int data[26], count;
} Ids;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    char **data;
    int count;
} Tokens;
typedef struct {
    Vec lo, hi;
} Bounds;
typedef struct {
    const char *name;
    Color color, second;
    I kd, ks, exponent, kr, kt, ior, checker_size;
} Material;
typedef enum { SPHERE, PLANE, BOX } ObjectKind;
typedef enum { POINT, SPOT, SUN, AREA } LightKind;
typedef struct {
    ObjectKind kind;
    char label;
    int material;
    Vec first, second;
    I radius;
} Object;
typedef struct {
    LightKind kind;
    Vec position, direction, u, v;
    I outer, inner, intensity;
    int divisions;
} Light;
typedef struct {
    Vec eye, forward, right, up;
    I half_width, half_height, ambient;
    Color background, fog_color;
    bool fog;
    I fog_start, fog_end;
    Material materials[26];
    Object objects[26];
    Light lights[9];
    int material_count, object_count, light_count;
} Scene;
typedef struct {
    int width, height, contrast, depth;
    I far, epsilon, pad;
} Settings;
typedef struct {
    Vec origin, direction;
} Ray;
typedef struct {
    I near, far;
    int near_axis, far_axis;
    bool valid;
} Slab;
typedef struct {
    I distance;
    bool entering;
    int axis;
    bool valid;
} Candidate;
typedef struct {
    I reflection, refraction;
    Vec direction;
    bool has_direction, total_internal;
} Weights;
void *allocate(size_t count, size_t size);
void release_all(void);
char *format(const char *pattern, ...);
void line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *name);
Tokens split_words(const char *text);
Vec parse_vec(Tokens tokens, int start);
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
Scene load_scene(void);
Slab slab(Bounds bounds, Ray ray);
Candidate intersect(Object object, Ray ray, I epsilon);
Vec outward_normal(Object object, Ray ray, Vec point, Candidate hit);
Bounds bounds(Object object, I pad);
Color base_color(Material material, Vec point);
void phong(Material material, Vec normal, Vec light, Vec view, I effective, I *diffuse, I *specular);
Vec reflected(Vec direction, Vec normal);
Weights refracted(Material material, Vec direction, Vec normal, bool front);
Color mix(Color local, I local_weight, Color reflection, I reflected_weight, Color refraction,
          I refracted_weight);
const char *object_kind(ObjectKind kind);
const char *light_kind(LightKind kind);
#endif
