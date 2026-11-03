#include "truss.hpp"
std::vector<Geometry> member_geometry(const Model &model,
                                      const std::vector<std::array<int, 2>> &dofs) {
    std::vector<Geometry> out;
    for (const Member &member : model.members) {
        int dx = model.nodes[member.end].x - model.nodes[member.start].x,
            dy = model.nodes[member.end].y - model.nodes[member.start].y;
        double length = std::sqrt(double(dx * dx + dy * dy));
        out.push_back({length,
                       double(dx) / length,
                       double(dy) / length,
                       {dofs[member.start][0], dofs[member.start][1], dofs[member.end][0],
                        dofs[member.end][1]}});
    }
    return out;
}
std::vector<Properties> member_properties(const Model &model, const Indices &choices,
                                          const std::vector<Geometry> &geometry) {
    std::vector<Properties> out;
    for (int i = 0; i < int(model.members.size()); ++i) {
        const Material &material = model.materials[model.members[i].material];
        const Section &section = model.sections[choices[i]];
        out.push_back({section.area, section.inertia, material.young, material.yield_stress,
                       material.density, material.expansion,
                       material.young * section.area / geometry[i].length});
    }
    return out;
}
double member_weight(const Properties &p, const Geometry &g) {
    return p.density * 9.81 * p.area * g.length / 1000000000;
}
std::array<std::array<double, 4>, 4> member_stiffness(const Properties &p, const Geometry &g) {
    double xx = p.stiffness * (g.cosine * g.cosine), xy = p.stiffness * (g.cosine * g.sine),
           yy = p.stiffness * (g.sine * g.sine);
    return {{{xx, xy, -xx, -xy}, {xy, yy, -xy, -yy}, {-xx, -xy, xx, xy}, {-xy, -yy, xy, yy}}};
}
Matrix assemble(const std::vector<Geometry> &geometry, const std::vector<Properties> &properties,
                int degrees, int removed) {
    Matrix out(degrees, Vector(degrees));
    for (int i = 0; i < int(geometry.size()); ++i)
        if (i != removed) {
            auto local = member_stiffness(properties[i], geometry[i]);
            for (int row = 0; row < 4; ++row)
                for (int column = 0; column < 4; ++column)
                    out[geometry[i].dofs[row]][geometry[i].dofs[column]] += local[row][column];
        }
    return out;
}
Loading load_vectors(const LoadCase &load_case, const std::vector<Geometry> &geometry,
                     const std::vector<Properties> &properties,
                     const std::vector<std::array<int, 2>> &node_dofs, int degrees, int removed) {
    Loading out{Vector(degrees), Vector(degrees), Vector(geometry.size()), false};
    Vector thermal(degrees);
    for (const Load &line : load_case.lines) {
        if (line.kind == LoadKind::Force) {
            out.external[node_dofs[line.index][0]] += line.x * 1000;
            out.external[node_dofs[line.index][1]] += line.y * 1000;
        } else if (line.kind == LoadKind::Temperature) {
            int index = line.index;
            if (index == removed)
                continue;
            const Properties &p = properties[index];
            const Geometry &g = geometry[index];
            double force = p.young * p.area * p.expansion * line.x;
            out.temperature[index] = force;
            std::array<double, 4> direction = {-g.cosine, -g.sine, g.cosine, g.sine};
            for (int i = 0; i < 4; ++i)
                thermal[g.dofs[i]] += force * direction[i];
        } else if (line.kind == LoadKind::Selfweight) {
            for (int index = 0; index < int(geometry.size()); ++index)
                if (index != removed) {
                    double weight = member_weight(properties[index], geometry[index]);
                    out.external[geometry[index].dofs[1]] -= weight / 2;
                    out.external[geometry[index].dofs[3]] -= weight / 2;
                }
        } else
            out.settlement = true;
    }
    for (int i = 0; i < degrees; ++i)
        out.total[i] = out.external[i] + thermal[i];
    return out;
}
