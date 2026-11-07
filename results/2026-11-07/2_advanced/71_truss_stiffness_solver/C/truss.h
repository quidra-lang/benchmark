#ifndef TRUSS_H
#define TRUSS_H
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#define MAX_NODES 40
#define MAX_MEMBERS 80
#define MAX_DOFS 80
#define MAX_CASES 10
#define MAX_RESULTS 20
#define PI 3.141592653589793
typedef struct {
    int id, x, y;
} Node;
typedef struct {
    int id, start, end, section, material;
    char group[13];
} Member;
typedef struct {
    char name[13];
    double area, inertia;
} Section;
typedef struct {
    char name[13];
    double young, yield_stress, density, expansion;
} Material;
typedef struct {
    int node;
    bool fixed[2];
    double prescribed[2];
} Support;
typedef enum { FORCE, TEMPERATURE, SELFWEIGHT, SETTLEMENT } LoadKind;
typedef struct {
    LoadKind kind;
    int index;
    double x, y;
} Load;
typedef struct {
    char name[13];
    Load lines[100];
    int count;
} LoadCase;
typedef struct {
    int index;
    double factor;
} Term;
typedef struct {
    char name[13];
    Term terms[10];
    int count;
} Combination;
typedef struct {
    int offset;
    double load;
} Axle;
typedef struct {
    char name[13];
    int magnification, horizontal, vertical;
} Drawing;
typedef struct {
    int deck[40], deck_count, *influence, influence_count, influence_capacity, vehicle_step;
    Axle axles[6];
    int axle_count;
    char rating[13], deflection[13], vibration[13], removal[13];
    double dead_factor, vehicle_factor, compression_limit, tension_limit;
    int deflection_ratio, modes, iterations, map_horizontal, map_vertical;
    Drawing *drawings;
    int drawing_count, drawing_capacity;
} Settings;
typedef struct {
    Node nodes[40];
    int node_count;
    Member members[80];
    int member_count;
    Section sections[20];
    int section_count;
    Material materials[5];
    int material_count;
    Support supports[10];
    int support_count;
    LoadCase cases[10];
    int case_count;
    Combination combinations[10];
    int combination_count;
    Settings settings;
} Model;
void read_model(Model *model);
typedef struct {
    double length, cosine, sine;
    int dofs[4];
} Geometry;
typedef struct {
    double area, inertia, young, yield_stress, density, expansion, stiffness;
} Properties;
typedef struct {
    double v[MAX_DOFS][MAX_DOFS];
    int n;
} Matrix;
typedef struct {
    double external[80], total[80], temperature[80];
    bool settlement;
} Loading;
void member_geometry(const Model *model, const int dofs[40][2], Geometry *geometry);
void member_properties(const Model *model, const int *choices, const Geometry *geometry,
                       Properties *properties);
double member_weight(const Properties *properties, const Geometry *geometry);
void assemble(const Geometry *geometry, const Properties *properties, int members, int degrees,
              int removed, Matrix *out);
void load_vectors(const LoadCase *load_case, const Geometry *geometry, const Properties *properties,
                  const int dofs[40][2], int members, int degrees, int removed, Loading *out);
int cholesky(const Matrix *matrix, const int *free_dofs, Matrix *lower);
void solve(const Matrix *lower, const double *right, double *solution);
typedef struct {
    char name[13];
    double displacement[80], forces[80], reactions[80], external[80];
} Result;
void axial_forces(const Geometry *geometry, const Properties *properties, int members,
                  const double *displacement, const double *temperature, int removed, double *out);
void reactions(const Matrix *matrix, const double *displacement, const double *force,
               const int *restrained, int nr, double *out);
void superpose(const Combination *combination, const Result *cases, int members, int degrees,
               Result *out);
double equilibrium_residual(const Result *result, const Geometry *geometry, int members,
                            int degrees);
double buckling(const Properties *properties, const Geometry *geometry, double inertia);
double utilization(double force, const Properties *properties, const Geometry *geometry,
                   const Section *section);
double slenderness(const Properties *properties, const Geometry *geometry, const Section *section);
double slenderness_limit(int member, const Result *combinations, int count, double compression,
                         double tension);
int select_section(const int *members, int member_count, const Section *sections, int section_count,
                   const Properties *properties, const Geometry *geometry,
                   const Result *combinations, int combination_count, const double *limits);
#endif
