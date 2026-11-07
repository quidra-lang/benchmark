#ifndef HEAT_H
#define HEAT_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdbool.h>
#include <math.h>
#include <float.h>
#include <sys/stat.h>
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    int width, height, count;
    double dx, thickness;
    char codes[1000];
    int neighbors[1000][4];
} Mesh;
typedef struct {
    char code, name[17];
    double k, rho, cp;
} Material;
typedef struct {
    int neighbor;
    double g, theta;
    bool boundary;
} Face;
typedef struct {
    int point, direction;
} CellFace;
typedef struct {
    char name[13], edge[7], kind[11];
    CellFace faces[40];
    int count;
    double coefficient, theta;
} Segment;
typedef struct {
    char name[13];
    int cells[1000], count, on[10], off[10], interval_count;
    double power;
} Source;
typedef struct {
    char name[13];
    int point;
} Probe;
typedef struct {
    char name[13], method[16];
    int step;
} Run;
typedef struct {
    double initial, tolerance, omega, alarm, limit, bands[9];
    int end, probe_every, max_iterations, snapshots[5], snapshot_count, probe_count, run_count,
        band_count;
    Probe probes[8];
    Run runs[8];
    char reference[13];
} Params;
typedef struct {
    Mesh mesh;
    Material materials[9];
    int material_count;
    Segment segments[20];
    int segment_count;
    Source sources[5];
    int source_count;
    Face faces[1000][4];
    int cell_material[1000];
    double capacity[1000], diagonal[1000], beta[1000], source_all[1000], total_power, dt_max;
} System;
typedef struct {
    char method[16];
    double *field, *changes, omega;
    int count;
    bool converged;
} Iteration;
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...);
char *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *path);
Mesh read_mesh(void);
int cell(const Mesh *mesh, int row, int column);
char *coordinates(const Mesh *mesh, int point);
void segment_faces(const Mesh *mesh, Segment *segment, int start, int end);
void source_cells(const Mesh *mesh, Source *source, int r1, int c1, int r2, int c2);
int read_materials(Material *materials);
double capacity(Material material, double dx, double thickness),
    interior(double first, double second, double thickness),
    fixed(double conductivity, double thickness),
    convective(double conductivity, double coefficient, double dx, double thickness);
double heat_flow(const System *system, const double *field, int point, int first, int last);
void thomas(const double *lower, const double *diagonal, const double *upper, const double *rhs,
            int count, double *out);
void sweep(const System *system, double tau, const double *rhs, bool horizontal, double *out);
void advance(const System *system, const double *field, const double *source, double dt,
             const char *method, double *out, double *intermediate);
double g_value(const System *system, const double *field, int point);
Iteration iterate(const System *system, const Params *params, const char *method, double omega);
double **direct(const System *system, double **rhs, int rhs_count);
double residual(const System *system, const double *field, const double *rhs);
char *real(double value, int digits), *time_text(int milliseconds);
int hottest(const double *field, int count);
char *summary(const char *prefix, const Mesh *mesh, const double *field);
void field_lines(Lines *lines, const Mesh *mesh, const double *field);
void isotherms(Lines *lines, const char *prefix, const Mesh *mesh, const double *field,
               const Params *params);
void save(const char *name, Lines lines);
#endif
