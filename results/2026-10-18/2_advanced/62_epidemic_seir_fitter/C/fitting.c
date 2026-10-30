#include "epidemic.h"
Golden golden(double (*function)(double, void *), void *context, double a, double b,
              int iterations) {
    const double phi = 0.6180339887498949;
    double c = b - phi * (b - a), d = a + phi * (b - a), fc = function(c, context),
           fd = function(d, context);
    Golden out = {0};
    out.records[out.count++] = (GoldenRecord){a, b, c, d, fc, fd};
    for (int i = 0; i < iterations; ++i) {
        if (fc < fd) {
            b = d;
            d = c;
            fd = fc;
            c = b - phi * (b - a);
            fc = function(c, context);
        } else {
            a = c;
            c = d;
            fc = fd;
            d = a + phi * (b - a);
            fd = function(d, context);
        }
        out.records[out.count++] = (GoldenRecord){a, b, c, d, fc, fd};
    }
    out.point = fc < fd ? c : d;
    out.value = fc < fd ? fc : fd;
    return out;
}
static int vertex_less(const void *a, const void *b) {
    const Vertex *x = a, *y = b;
    return x->value != y->value ? (x->value < y->value ? -1 : 1) : x->number - y->number;
}
static Point along(Point first, double factor, Point second) {
    Point out = {{first.value[0] + factor * (second.value[0] - first.value[0]),
                  first.value[1] + factor * (second.value[1] - first.value[1])}};
    return out;
}
Simplex nelder_mead(double (*function)(Point, void *), void *context, Point start,
                    const Params *params) {
    Simplex out = {0};
    Point points[3] = {start,
                       {{start.value[0] + params->delta_beta, start.value[1]}},
                       {{start.value[0], start.value[1] + params->delta_gamma}}};
    int serial = 0;
    Vertex vertices[3];
    for (int i = 0; i < 3; ++i) {
        vertices[i] = (Vertex){points[i], function(points[i], context), serial++};
        out.initial[i] = vertices[i];
    }
    for (int iteration = 0; iteration < params->nelder; ++iteration) {
        qsort(vertices, 3, sizeof(Vertex), vertex_less);
        Vertex first = vertices[0], second = vertices[1], third = vertices[2];
        Point centroid = {{(first.point.value[0] + second.point.value[0]) / 2,
                           (first.point.value[1] + second.point.value[1]) / 2}},
              reflected = {
                  {centroid.value[0] + params->alpha * (centroid.value[0] - third.point.value[0]),
                   centroid.value[1] + params->alpha * (centroid.value[1] - third.point.value[1])}};
        double fr = function(reflected, context), value = fr;
        Point accepted = reflected;
        const char *operation = "reflect";
        bool shrink = false;
        if (fr < first.value) {
            Point expanded = along(centroid, params->chi, reflected);
            double fe = function(expanded, context);
            if (fe < fr) {
                accepted = expanded;
                value = fe;
                operation = "expand";
            }
        } else if (fr < second.value) {
        } else if (fr < third.value) {
            Point contracted = along(centroid, params->psi, reflected);
            double fc = function(contracted, context);
            if (fc <= fr) {
                accepted = contracted;
                value = fc;
                operation = "contract_out";
            } else
                shrink = true;
        } else {
            Point contracted = along(centroid, params->psi, third.point);
            double fc = function(contracted, context);
            if (fc < third.value) {
                accepted = contracted;
                value = fc;
                operation = "contract_in";
            } else
                shrink = true;
        }
        if (shrink) {
            operation = "shrink";
            for (int i = 1; i < 3; ++i) {
                Point point = along(first.point, params->omega, vertices[i].point);
                vertices[i] = (Vertex){point, function(point, context), serial++};
            }
        } else
            vertices[2] = (Vertex){accepted, value, serial++};
        qsort(vertices, 3, sizeof(Vertex), vertex_less);
        out.records[out.count++] = (SimplexRecord){operation, vertices[0]};
    }
    qsort(vertices, 3, sizeof(Vertex), vertex_less);
    memcpy(out.final, vertices, sizeof(vertices));
    return out;
}
