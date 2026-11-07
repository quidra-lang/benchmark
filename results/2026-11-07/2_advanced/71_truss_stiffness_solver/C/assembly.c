#include "truss.h"
void member_geometry(const Model *m, const int dofs[40][2], Geometry *out) {
    for (int i = 0; i < m->member_count; ++i) {
        const Member *member = &m->members[i];
        int dx = m->nodes[member->end].x - m->nodes[member->start].x,
            dy = m->nodes[member->end].y - m->nodes[member->start].y;
        double length = sqrt((double)(dx * dx + dy * dy));
        out[i] = (Geometry){length,
                            dx / length,
                            dy / length,
                            {dofs[member->start][0], dofs[member->start][1], dofs[member->end][0],
                             dofs[member->end][1]}};
    }
}
void member_properties(const Model *m, const int *choices, const Geometry *geometry,
                       Properties *out) {
    for (int i = 0; i < m->member_count; ++i) {
        const Material *a = &m->materials[m->members[i].material];
        const Section *s = &m->sections[choices[i]];
        out[i] = (Properties){s->area,
                              s->inertia,
                              a->young,
                              a->yield_stress,
                              a->density,
                              a->expansion,
                              a->young * s->area / geometry[i].length};
    }
}
double member_weight(const Properties *p, const Geometry *g) {
    return p->density * 9.81 * p->area * g->length / 1000000000;
}
void assemble(const Geometry *geometry, const Properties *properties, int members, int degrees,
              int removed, Matrix *out) {
    memset(out, 0, sizeof *out);
    out->n = degrees;
    for (int i = 0; i < members; ++i)
        if (i != removed) {
            const Geometry *g = &geometry[i];
            double k = properties[i].stiffness, xx = k * (g->cosine * g->cosine),
                   xy = k * (g->cosine * g->sine), yy = k * (g->sine * g->sine);
            double local[4][4] = {
                {xx, xy, -xx, -xy}, {xy, yy, -xy, -yy}, {-xx, -xy, xx, xy}, {-xy, -yy, xy, yy}};
            for (int r = 0; r < 4; ++r)
                for (int c = 0; c < 4; ++c)
                    out->v[g->dofs[r]][g->dofs[c]] += local[r][c];
        }
}
void load_vectors(const LoadCase *load_case, const Geometry *geometry, const Properties *properties,
                  const int dofs[40][2], int members, int degrees, int removed, Loading *out) {
    memset(out, 0, sizeof *out);
    double thermal[80] = {0};
    for (int line = 0; line < load_case->count; ++line) {
        const Load *load = &load_case->lines[line];
        if (load->kind == FORCE) {
            out->external[dofs[load->index][0]] += load->x * 1000;
            out->external[dofs[load->index][1]] += load->y * 1000;
        } else if (load->kind == TEMPERATURE) {
            int i = load->index;
            if (i == removed)
                continue;
            const Properties *p = &properties[i];
            const Geometry *g = &geometry[i];
            double force = p->young * p->area * p->expansion * load->x;
            out->temperature[i] = force;
            double direction[4] = {-g->cosine, -g->sine, g->cosine, g->sine};
            for (int j = 0; j < 4; ++j)
                thermal[g->dofs[j]] += force * direction[j];
        } else if (load->kind == SELFWEIGHT) {
            for (int i = 0; i < members; ++i)
                if (i != removed) {
                    double weight = member_weight(&properties[i], &geometry[i]);
                    out->external[geometry[i].dofs[1]] -= weight / 2;
                    out->external[geometry[i].dofs[3]] -= weight / 2;
                }
        } else
            out->settlement = true;
    }
    for (int i = 0; i < degrees; ++i)
        out->total[i] = out->external[i] + thermal[i];
}
