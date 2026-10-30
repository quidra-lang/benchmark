#include "truss.h"
double buckling(const Properties *p, const Geometry *g, double inertia) {
    return PI * PI * p->young * inertia / (g->length * g->length);
}
double utilization(double force, const Properties *p, const Geometry *g, const Section *section) {
    double area = section ? section->area : p->area,
           inertia = section ? section->inertia : p->inertia;
    return fmax(fabs(force / area) / p->yield_stress, fmax(0, -force) / buckling(p, g, inertia));
}
double slenderness(const Properties *p, const Geometry *g, const Section *section) {
    double area = section ? section->area : p->area,
           inertia = section ? section->inertia : p->inertia;
    return g->length / sqrt(inertia / area);
}
double slenderness_limit(int member, const Result *combinations, int count, double compression,
                         double tension) {
    for (int i = 0; i < count; ++i)
        if (combinations[i].forces[member] < 0)
            return compression;
    return tension;
}
int select_section(const int *members, int member_count, const Section *sections, int section_count,
                   const Properties *properties, const Geometry *geometry,
                   const Result *combinations, int combination_count, const double *limits) {
    for (int index = 0; index < section_count; ++index) {
        bool acceptable = true;
        for (int i = 0; i < member_count; ++i) {
            int m = members[i];
            if (slenderness(&properties[m], &geometry[m], &sections[index]) > limits[m]) {
                acceptable = false;
                break;
            }
            for (int j = 0; j < combination_count; ++j)
                if (utilization(combinations[j].forces[m], &properties[m], &geometry[m],
                                &sections[index]) > 1) {
                    acceptable = false;
                    break;
                }
            if (!acceptable)
                break;
        }
        if (acceptable)
            return index;
    }
    return section_count - 1;
}
