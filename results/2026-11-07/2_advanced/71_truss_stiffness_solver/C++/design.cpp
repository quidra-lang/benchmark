#include "truss.hpp"
double buckling(const Properties &p, const Geometry &g, double inertia) {
    return pi * pi * p.young * inertia / (g.length * g.length);
}
double utilization(double force, const Properties &p, const Geometry &g, const Section *section) {
    double area = section ? section->area : p.area,
           inertia = section ? section->inertia : p.inertia;
    return std::max(std::abs(force / area) / p.yield_stress,
                    std::max(0.0, -force) / buckling(p, g, inertia));
}
double slenderness(const Properties &p, const Geometry &g, const Section *section) {
    double area = section ? section->area : p.area,
           inertia = section ? section->inertia : p.inertia;
    return g.length / std::sqrt(inertia / area);
}
double slenderness_limit(int number, const std::vector<Result> &combinations, double compression,
                         double tension) {
    for (const Result &result : combinations)
        if (result.forces[number] < 0)
            return compression;
    return tension;
}
int select_section(const Indices &members, const std::vector<Section> &sections,
                   const std::vector<Properties> &properties, const std::vector<Geometry> &geometry,
                   const std::vector<Result> &combinations, const Vector &limits) {
    for (int index = 0; index < int(sections.size()); ++index) {
        bool acceptable = true;
        for (int member : members) {
            if (slenderness(properties[member], geometry[member], &sections[index]) >
                limits[member]) {
                acceptable = false;
                break;
            }
            for (const Result &result : combinations)
                if (utilization(result.forces[member], properties[member], geometry[member],
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
    return int(sections.size()) - 1;
}
