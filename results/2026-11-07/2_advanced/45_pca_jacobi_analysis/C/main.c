#include "analysis.h"
const char *real(double value, int precision) {
    static char buffers[128][96];
    static unsigned next;
    char *out = buffers[next++ % 128];
    if (fabs(value) < 0.5 * pow(10.0, -precision))
        value = 0;
    snprintf(out, 96, "%.*f", precision, value);
    return out;
}
static double sum(Vector values) {
    double out = 0;
    for (int i = 0; i < values.n; ++i)
        out += values.v[i];
    return out;
}
static void decreasing(Vector values, int *out) {
    for (int i = 0; i < values.n; ++i) {
        int position = i;
        while (position > 0 && values.v[i] > values.v[out[position - 1]]) {
            out[position] = out[position - 1];
            --position;
        }
        out[position] = i;
    }
}
typedef struct {
    int observed;
    double mean, sd, minimum, maximum, msa;
} Summary;
typedef struct {
    int n;
    Sample rows[300];
    Matrix values, cov, cor, matrix, z;
    Vector mean, sd, scale;
    Eigen eigen;
} Analysis;
static Analysis *analyze(const Input *input, Vector observed_means, const char *missing,
                         const char *scaling) {
    Analysis *out = calloc(1, sizeof *out);
    out->values.cols = input->p;
    for (int i = 0; i < input->n; ++i) {
        const Sample *row = &input->data[i];
        bool complete = true;
        for (int j = 0; j < input->p; ++j)
            if (row->missing[j])
                complete = false;
        if (strcmp(missing, "listwise") == 0 && !complete)
            continue;
        Sample *copy = &out->rows[out->n];
        *copy = *row;
        for (int j = 0; j < input->p; ++j) {
            if (copy->missing[j])
                copy->values[j] = observed_means.v[j];
            copy->missing[j] = false;
            out->values.v[out->n][j] = copy->values[j];
        }
        ++out->n;
    }
    out->values.rows = out->n;
    out->mean = means(&out->values);
    out->cov = covariance(&out->values, out->mean);
    out->sd = vector(input->p);
    out->scale = vector(input->p);
    for (int j = 0; j < input->p; ++j) {
        out->sd.v[j] = sqrt(out->cov.v[j][j]);
        out->scale.v[j] = strcmp(scaling, "covariance") == 0 ? 1 : out->sd.v[j];
    }
    out->cor = correlation(&out->cov, out->sd);
    out->matrix = strcmp(scaling, "covariance") == 0 ? out->cov : out->cor;
    out->z = matrix(out->n, input->p);
    for (int i = 0; i < out->n; ++i) {
        const Vector z = standardize(&out->rows[i], out->mean, out->scale);
        for (int j = 0; j < input->p; ++j)
            out->z.v[i][j] = z.v[j];
    }
    out->eigen = jacobi(&out->matrix);
    return out;
}
static const char *flag(double t2, double spe, const Params *p) {
    return t2 > p->t2 ? (spe > p->spe ? "TQ" : "T") : (spe > p->spe ? "Q" : "-");
}
typedef struct {
    Vector z, score, residual, tcontribution, qcontribution;
    double t2, spe, quality;
    const char *flag;
} Diagnostic;
static Diagnostic diagnose(Vector z, const Eigen *eigen, int count, const Params *p) {
    Diagnostic out = {0};
    out.z = z;
    out.score = scores(z, &eigen->vectors);
    out.residual = residuals(z, out.score, &eigen->vectors, count);
    out.t2 = hotelling(out.score, eigen->values, count);
    out.spe = dot(out.residual, out.residual);
    double represented = 0;
    for (int k = 0; k < count; ++k)
        represented += out.score.v[k] * out.score.v[k];
    out.quality = represented / dot(z, z);
    out.flag = flag(out.t2, out.spe, p);
    out.tcontribution = vector(z.n);
    out.qcontribution = vector(z.n);
    for (int j = 0; j < z.n; ++j) {
        double weight = 0;
        for (int k = 0; k < count; ++k)
            weight += (out.score.v[k] / eigen->values.v[k]) * eigen->vectors.v[k][j];
        out.tcontribution.v[j] = z.v[j] * weight;
        out.qcontribution.v[j] = out.residual.v[j] * out.residual.v[j];
    }
    return out;
}
static double criterion(const Matrix *g) {
    double out = 0;
    for (int k = 0; k < g->cols; ++k) {
        double q2 = 0, q4 = 0;
        for (int j = 0; j < g->rows; ++j) {
            const double value = g->v[j][k];
            q2 += value * value;
            q4 += (value * value) * (value * value);
        }
        out += q4 / g->rows - (q2 / g->rows) * (q2 / g->rows);
    }
    return out;
}
static Vector row_vector(const Matrix *matrix, int i) {
    Vector out = vector(matrix->cols);
    for (int j = 0; j < out.n; ++j)
        out.v[j] = matrix->v[i][j];
    return out;
}
static bool inside(int r, int c, int rc, int cc, int rho) {
    return (c - cc) * (c - cc) + (2 * (r - rc)) * (2 * (r - rc)) <= rho * rho;
}
static void plots(const Input *input, const Analysis *a, const Matrix *loadings, const Vector *broken,
                  double total, double average, const Diagnostic *d, const Diagnostic *s) {
    const Params *p = &input->params;
    const Eigen *e = &a->eigen;
    FILE *out = fopen("output/plots.txt", "w");
    const int kc = (int)floor(average / e->values.v[0] * p->scree + 0.5);
    fprintf(out, "scree width %d kaiser_column %d\n", p->scree, kc);
    for (int k = 0; k < input->p; ++k) {
        const int length = (int)floor(e->values.v[k] / e->values.v[0] * p->scree + 0.5),
                  position = (int)floor(broken->v[k] * total / e->values.v[0] * p->scree + 0.5);
        scree_line(out, length, kc, position, p->scree);
        fprintf(out, " pc%d %s\n", k + 1, real(e->values.v[k], 4));
    }
    double m1 = 0, m2 = 0, l1 = 0, l2 = 0;
    for (int set = 0; set < 2; ++set) {
        const Diagnostic *items = set ? s : d;
        const int count = set ? input->ns : a->n;
        for (int i = 0; i < count; ++i) {
            m1 = fmax(m1, fabs(items[i].score.v[0]));
            m2 = fmax(m2, fabs(items[i].score.v[1]));
        }
    }
    for (int j = 0; j < input->p; ++j) {
        l1 = fmax(l1, fabs(loadings->v[j][0]));
        l2 = fmax(l2, fabs(loadings->v[j][1]));
    }
    const double scale = 0.9 * fmin(m1 / l1, m2 / l2);
    Grid biplot = grid(p->bh, p->bw);
    const Cell origin = biplot_cell(0, 0, m1, m2, p->bw, p->bh);
    memset(biplot.cells[origin.row], '-', (size_t)p->bw);
    for (int r = 0; r < p->bh; ++r)
        biplot.cells[r][origin.column] = '|';
    biplot.cells[origin.row][origin.column] = '+';
    Cell tips[12];
    for (int j = 0; j < input->p; ++j) {
        tips[j] = biplot_cell(scale * loadings->v[j][0], scale * loadings->v[j][1], m1, m2, p->bw, p->bh);
        shaft_cells(&biplot, origin, tips[j]);
    }
    int counts[40][80] = {0};
    for (int i = 0; i < a->n; ++i) {
        const Cell cell = biplot_cell(d[i].score.v[0], d[i].score.v[1], m1, m2, p->bw, p->bh);
        ++counts[cell.row][cell.column];
    }
    for (int r = 0; r < p->bh; ++r)
        for (int c = 0; c < p->bw; ++c)
            if (counts[r][c])
                biplot.cells[r][c] = counts[r][c] == 1 ? '.' : counts[r][c] <= 3 ? 'o' : '@';
    for (int i = 0; i < a->n; ++i)
        if (strcmp(d[i].flag, "-") != 0) {
            const Cell cell = biplot_cell(d[i].score.v[0], d[i].score.v[1], m1, m2, p->bw, p->bh);
            biplot.cells[cell.row][cell.column] = 'X';
        }
    for (int i = 0; i < input->ns; ++i) {
        const Cell cell = biplot_cell(s[i].score.v[0], s[i].score.v[1], m1, m2, p->bw, p->bh);
        biplot.cells[cell.row][cell.column] = '*';
    }
    for (int j = 0; j < input->p; ++j)
        biplot.cells[tips[j].row][tips[j].column] = (char)('A' + j);
    fprintf(out, "\nbiplot pc1 pc2 width %d height %d\nx %s %s y %s %s arrow_scale %s\n", p->bw, p->bh,
            real(-m1, 4), real(m1, 4), real(-m2, 4), real(m2, 4), real(scale, 4));
    framed(out, &biplot);
    for (int j = 0; j < input->p; ++j)
        fprintf(out, "%c %s %s %s\n", 'A' + j, input->names[j], real(loadings->v[j][0], 4),
                real(loadings->v[j][1], 4));
    const int rho = p->radius, rc = rho / 2 + 1, cc = rho + 1;
    Grid circle = grid(rho + 3, 2 * rho + 3);
    memset(circle.cells[rc], '-', (size_t)circle.width);
    for (int r = 0; r < circle.height; ++r)
        circle.cells[r][cc] = '|';
    circle.cells[rc][cc] = '+';
    for (int r = 0; r < circle.height; ++r)
        for (int c = 0; c < circle.width; ++c)
            if (inside(r, c, rc, cc, rho) &&
                (!inside(r - 1, c, rc, cc, rho) || !inside(r + 1, c, rc, cc, rho) ||
                 !inside(r, c - 1, rc, cc, rho) || !inside(r, c + 1, rc, cc, rho)))
                circle.cells[r][c] = '.';
    for (int j = 0; j < input->p; ++j) {
        const Cell cell = circle_cell(loadings->v[j][0] / sqrt(a->matrix.v[j][j]),
                                      loadings->v[j][1] / sqrt(a->matrix.v[j][j]), rho);
        circle.cells[cell.row][cell.column] = (char)('A' + j);
    }
    fprintf(out, "\ncircle radius %d\n", rho);
    framed(out, &circle);
    for (int j = 0; j < input->p; ++j) {
        const double q1 = loadings->v[j][0] / sqrt(a->matrix.v[j][j]),
                     q2 = loadings->v[j][1] / sqrt(a->matrix.v[j][j]);
        fprintf(out, "%c %s %s %s %s\n", 'A' + j, input->names[j], real(q1, 4), real(q2, 4),
                real(q1 * q1 + q2 * q2, 4));
    }
    Grid diagnostic = grid(p->dh, p->dw);
    const Cell limit = diagnostic_cell(p->t2, p->spe, 2 * p->t2, 2 * p->spe, p->dw, p->dh);
    memset(diagnostic.cells[limit.row], '-', (size_t)p->dw);
    for (int r = 0; r < p->dh; ++r)
        diagnostic.cells[r][limit.column] = '|';
    diagnostic.cells[limit.row][limit.column] = '+';
    memset(counts, 0, sizeof counts);
    for (int i = 0; i < a->n; ++i) {
        const Cell cell = diagnostic_cell(d[i].t2, d[i].spe, 2 * p->t2, 2 * p->spe, p->dw, p->dh);
        ++counts[cell.row][cell.column];
    }
    for (int r = 0; r < p->dh; ++r)
        for (int c = 0; c < p->dw; ++c)
            if (counts[r][c])
                diagnostic.cells[r][c] = counts[r][c] == 1 ? '.' : counts[r][c] <= 3 ? 'o' : '@';
    for (int i = 0; i < input->ns; ++i) {
        const Cell cell = diagnostic_cell(s[i].t2, s[i].spe, 2 * p->t2, 2 * p->spe, p->dw, p->dh);
        diagnostic.cells[cell.row][cell.column] = '*';
    }
    fprintf(out, "\ndiagnostic width %d height %d t2_max %s spe_max %s\n", p->dw, p->dh, real(2 * p->t2, 4),
            real(2 * p->spe, 4));
    framed(out, &diagnostic);
    fclose(out);
}
int main(void) {
    mkdir("output", 0777);
    const Input input = read_input();
    const Params *p = &input.params;
    const int variables = input.p;
    Summary summary[12] = {0};
    Vector observed_means = vector(variables);
    int incomplete[300], nincomplete = 0;
    for (int i = 0; i < input.n; ++i) {
        bool missing = false;
        for (int j = 0; j < variables; ++j)
            if (input.data[i].missing[j])
                missing = true;
        if (missing)
            incomplete[nincomplete++] = i;
    }
    for (int j = 0; j < variables; ++j) {
        Vector observed = vector(0);
        for (int i = 0; i < input.n; ++i)
            if (!input.data[i].missing[j])
                observed.v[observed.n++] = input.data[i].values[j];
        Summary *s = &summary[j];
        s->observed = observed.n;
        s->mean = sum(observed) / s->observed;
        observed_means.v[j] = s->mean;
        double squares = 0;
        s->minimum = s->maximum = observed.v[0];
        for (int i = 0; i < observed.n; ++i) {
            const double value = observed.v[i];
            squares += (value - s->mean) * (value - s->mean);
            s->minimum = fmin(s->minimum, value);
            s->maximum = fmax(s->maximum, value);
        }
        s->sd = sqrt(squares / (s->observed - 1));
    }
    Analysis *a = analyze(&input, observed_means, p->missing, p->scaling);
    const Eigen *e = &a->eigen;
    const int n = a->n;
    const double total = sum(e->values), average = total / variables;
    Vector ratio = vector(variables), cumulative = vector(variables), broken = vector(variables),
           parallel = vector(variables), errors = vector(variables);
    int kaiser = 0, broken_count = variables, parallel_count = variables, cumulative_count = variables;
    for (int k = 0; k < variables; ++k) {
        ratio.v[k] = e->values.v[k] / total;
        cumulative.v[k] = (k ? cumulative.v[k - 1] : 0) + ratio.v[k];
        for (int i = k + 1; i <= variables; ++i)
            broken.v[k] += 1.0 / i;
        broken.v[k] /= variables;
        errors.v[k] = e->values.v[k] * sqrt(2.0 / n);
        kaiser += e->values.v[k] > average;
    }
    int64_t state = p->seed;
    for (int r = 0; r < p->repetitions; ++r) {
        Matrix random = matrix(n, variables);
        for (int i = 0; i < n; ++i)
            for (int j = 0; j < variables; ++j) {
                state = (48271 * state) % 2147483647;
                random.v[i][j] = (double)state / 2147483647;
            }
        const Matrix cov = covariance(&random, means(&random));
        Vector sd = vector(variables);
        for (int j = 0; j < variables; ++j)
            sd.v[j] = sqrt(cov.v[j][j]);
        const Matrix cor = correlation(&cov, sd);
        const Eigen result = jacobi(&cor);
        const double variance = sum(result.values);
        for (int k = 0; k < variables; ++k)
            parallel.v[k] += result.values.v[k] / variance;
    }
    for (int k = 0; k < variables; ++k) {
        parallel.v[k] /= p->repetitions;
        if (broken_count == variables && ratio.v[k] <= broken.v[k])
            broken_count = k;
        if (parallel_count == variables && ratio.v[k] <= parallel.v[k])
            parallel_count = k;
        if (cumulative_count == variables && cumulative.v[k] >= p->cumulative)
            cumulative_count = k + 1;
    }
    int retained;
    if (strcmp(p->components, "kaiser") == 0)
        retained = kaiser;
    else if (strcmp(p->components, "broken_stick") == 0)
        retained = broken_count;
    else if (strcmp(p->components, "parallel") == 0)
        retained = parallel_count;
    else if (strcmp(p->components, "cumulative") == 0)
        retained = cumulative_count;
    else
        retained = atoi(p->components);
    if (retained == 0)
        retained = 1;
    const Inverse inverse = inverse_determinant(&a->cor);
    double rr_total = 0, pp_total = 0;
    for (int j = 0; j < variables; ++j) {
        double rr = 0, pp = 0;
        for (int k = 0; k < variables; ++k)
            if (j != k) {
                const double partial =
                    -inverse.inverse.v[j][k] / sqrt(inverse.inverse.v[j][j] * inverse.inverse.v[k][k]);
                rr += a->cor.v[j][k] * a->cor.v[j][k];
                pp += partial * partial;
            }
        summary[j].msa = rr / (rr + pp);
        rr_total += rr;
        pp_total += pp;
    }
    const double kmo = rr_total / (rr_total + pp_total),
                 bartlett = -(n - 1 - (2.0 * variables + 5) / 6) * log(inverse.determinant);
    Matrix loadings = matrix(variables, variables);
    Vector communality = vector(variables);
    for (int j = 0; j < variables; ++j) {
        for (int k = 0; k < variables; ++k)
            loadings.v[j][k] = e->vectors.v[k][j] * sqrt(e->values.v[k]);
        for (int k = 0; k < retained; ++k)
            communality.v[j] += loadings.v[j][k] * loadings.v[j][k];
        communality.v[j] /= a->matrix.v[j][j];
    }
    Matrix g = matrix(variables, retained);
    Vector eta = vector(variables), criteria = vector(p->cycles + 1);
    for (int j = 0; j < variables; ++j) {
        for (int k = 0; k < retained; ++k)
            eta.v[j] += loadings.v[j][k] * loadings.v[j][k];
        eta.v[j] = sqrt(eta.v[j]);
        for (int k = 0; k < retained; ++k)
            g.v[j][k] = loadings.v[j][k] / eta.v[j];
    }
    criteria.v[0] = criterion(&g);
    for (int cycle = 0; cycle < p->cycles; ++cycle) {
        for (int left = 0; left < retained - 1; ++left)
            for (int right = left + 1; right < retained; ++right) {
                double sa = 0, sb = 0, sc = 0, sd = 0;
                for (int j = 0; j < variables; ++j) {
                    const double x = g.v[j][left], y = g.v[j][right], phi = x * x - y * y, psi = 2 * x * y;
                    sa += phi;
                    sb += psi;
                    sc += phi * phi - psi * psi;
                    sd += 2 * phi * psi;
                }
                const double num = sd - 2 * sa * sb / variables, den = sc - (sa * sa - sb * sb) / variables,
                             omega = sqrt(num * num + den * den);
                if (omega == 0)
                    continue;
                const double cos4 = den / omega, sin4 = num / omega, cos2 = sqrt((1 + cos4) / 2),
                             sin2 = cos2 == 0 ? 1 : sin4 / (2 * cos2), cos1 = sqrt((1 + cos2) / 2),
                             sin1 = sin2 / (2 * cos1);
                for (int j = 0; j < variables; ++j) {
                    const double x = g.v[j][left], y = g.v[j][right];
                    g.v[j][left] = cos1 * x + sin1 * y;
                    g.v[j][right] = -sin1 * x + cos1 * y;
                }
            }
        criteria.v[cycle + 1] = criterion(&g);
    }
    Matrix rotated = matrix(retained, variables);
    Vector rotated_ss = vector(retained);
    for (int k = 0; k < retained; ++k) {
        Vector values = vector(variables);
        for (int j = 0; j < variables; ++j)
            values.v[j] = g.v[j][k] * eta.v[j];
        values = orient(values);
        rotated_ss.v[k] = dot(values, values);
        for (int j = 0; j < variables; ++j)
            rotated.v[k][j] = values.v[j];
    }
    int rotated_order[12];
    decreasing(rotated_ss, rotated_order);
    Diagnostic *d = calloc((size_t)n, sizeof *d), *s = calloc((size_t)input.ns, sizeof *s);
    for (int i = 0; i < n; ++i)
        d[i] = diagnose(row_vector(&a->z, i), e, retained, p);
    for (int i = 0; i < input.ns; ++i)
        s[i] = diagnose(standardize(&input.supplementary[i], a->mean, a->scale), e, retained, p);
    Power power[12];
    power_iteration(&a->matrix, e, power);
    FILE *out = fopen("output/eigen.txt", "w");
    fprintf(out, "pca rows %d used %d variables %d missing %s scaling %s\nincomplete %d", input.n, n,
            variables, p->missing, p->scaling, nincomplete);
    if (!nincomplete)
        fputs(" -", out);
    for (int i = 0; i < nincomplete; ++i)
        fprintf(out, " %s", input.data[incomplete[i]].id);
    fputs("\n\nvariable observed missing mean sd min max msa\n", out);
    for (int j = 0; j < variables; ++j) {
        const Summary *x = &summary[j];
        fprintf(out, "%s %d %d %s %s %s %s %s\n", input.names[j], x->observed, input.n - x->observed,
                real(x->mean, 4), real(x->sd, 4), real(x->minimum, 4), real(x->maximum, 4), real(x->msa, 4));
    }
    fprintf(out, "adequacy kmo %s determinant %s bartlett %s df %d\n\nmatrix %s\n", real(kmo, 4),
            real(inverse.determinant, 6), real(bartlett, 4), variables * (variables - 1) / 2, p->scaling);
    for (int j = 0; j < variables; ++j) {
        fputs(input.names[j], out);
        for (int k = 0; k < variables; ++k)
            fprintf(out, " %s", real(a->matrix.v[j][k], 4));
        fputc('\n', out);
    }
    typedef struct {
        int a, b;
        double magnitude;
    } Pair;
    Pair pairs[66];
    int pair_count = 0;
    for (int j = 0; j < variables - 1; ++j)
        for (int k = j + 1; k < variables; ++k) {
            Pair pair = {j, k, fabs(a->cor.v[j][k])};
            int position = pair_count;
            while (position > 0 && pair.magnitude > pairs[position - 1].magnitude) {
                pairs[position] = pairs[position - 1];
                --position;
            }
            pairs[position] = pair;
            ++pair_count;
        }
    fputs("strongest", out);
    for (int i = 0; i < p->top && i < pair_count; ++i)
        fprintf(out, " %s:%s:%s", input.names[pairs[i].a], input.names[pairs[i].b],
                real(a->cor.v[pairs[i].a][pairs[i].b], 4));
    fprintf(
        out,
        "\n\njacobi sweeps %d\neigenvalues total %s average %s\nk eigenvalue ratio cumulative broken_stick parallel se separated\n",
        e->sweeps, real(total, 4), real(average, 4));
    for (int k = 0; k < variables; ++k) {
        const bool separated =
            (k == 0 || fabs(e->values.v[k] - e->values.v[k - 1]) > errors.v[k]) &&
            (k + 1 == variables || fabs(e->values.v[k] - e->values.v[k + 1]) > errors.v[k]);
        fprintf(out, "%d %s %s %s %s %s %s %s\n", k + 1, real(e->values.v[k], 4), real(ratio.v[k], 4),
                real(cumulative.v[k], 4), real(broken.v[k], 4), real(parallel.v[k], 4), real(errors.v[k], 4),
                separated ? "yes" : "no");
    }
    fprintf(
        out,
        "retention kaiser %d broken_stick %d parallel %d cumulative %d target %s\ncomponents %d rule %s\n\neigenvectors\nvariable",
        kaiser, broken_count, parallel_count, cumulative_count, real(p->cumulative, 4), retained,
        p->components);
    for (int k = 0; k < variables; ++k)
        fprintf(out, " pc%d", k + 1);
    fputc('\n', out);
    for (int j = 0; j < variables; ++j) {
        fputs(input.names[j], out);
        for (int k = 0; k < variables; ++k)
            fprintf(out, " %s", real(e->vectors.v[k][j], 4));
        fputc('\n', out);
    }
    fputs("\npower_iteration iterations 1000\nk jacobi power agree_at match\n", out);
    int matches = 0;
    for (int k = 0; k < variables; ++k) {
        const bool match = fabs(power[k].value - e->values.v[k]) <= 1e-8 * e->values.v[0] &&
                           difference(power[k].vector, row_vector(&e->vectors, k)) <= 0.000001;
        matches += match;
        fprintf(out, "%d %s %s ", k + 1, real(e->values.v[k], 4), real(power[k].value, 4));
        if (power[k].agreement)
            fprintf(out, "%d", power[k].agreement);
        else
            fputc('-', out);
        fprintf(out, " %s\n", match ? "yes" : "no");
    }
    fprintf(out, "cross_check %d/%d\n\nscores\ncomponent sd min min_id max max_id contributors\n", matches,
            variables);
    for (int k = 0; k < retained; ++k) {
        Vector contribution = vector(n);
        double squares = 0;
        int minimum = 0, maximum = 0;
        for (int i = 0; i < n; ++i) {
            const double value = d[i].score.v[k];
            squares += value * value;
            contribution.v[i] = value * value / ((n - 1) * e->values.v[k]);
            if (value < d[minimum].score.v[k])
                minimum = i;
            if (value > d[maximum].score.v[k])
                maximum = i;
        }
        fprintf(out, "pc%d %s %s %s %s %s", k + 1, real(sqrt(squares / (n - 1)), 4),
                real(d[minimum].score.v[k], 4), a->rows[minimum].id, real(d[maximum].score.v[k], 4),
                a->rows[maximum].id);
        int order[300];
        decreasing(contribution, order);
        for (int i = 0; i < p->top && i < n; ++i)
            fprintf(out, " %s:%s", a->rows[order[i]].id, real(contribution.v[order[i]], 4));
        fputc('\n', out);
    }
    fprintf(out, "\nvarimax components %d cycles %d\n", retained, p->cycles);
    for (int cycle = 0; cycle <= p->cycles; ++cycle)
        fprintf(out, "cycle %d criterion %s\n", cycle, real(criteria.v[cycle], 6));
    for (int k = 0; k < retained; ++k) {
        const int source = rotated_order[k];
        const Vector values = row_vector(&rotated, source);
        int closest = 0;
        double congruence = -1;
        for (int h = 0; h < retained; ++h) {
            const Vector loading = column(&loadings, h);
            const double value =
                fabs(dot(values, loading) / sqrt(dot(values, values) * dot(loading, loading)));
            if (value > congruence) {
                congruence = value;
                closest = h;
            }
        }
        fprintf(out, "rc%d ss %s ratio %s closest pc%d congruence %s\n", k + 1, real(rotated_ss.v[source], 4),
                real(rotated_ss.v[source] / total, 4), closest + 1, real(congruence, 4));
    }
    fputs("\nsensitivity\nmissing scaling rows sweeps eigenvalues cumulative congruence\n", out);
    const char *strategies[] = {"listwise", "mean"}, *scalings[] = {"covariance", "correlation"};
    for (int m = 0; m < 2; ++m)
        for (int scaling = 0; scaling < 2; ++scaling) {
            Analysis *alternative = analyze(&input, observed_means, strategies[m], scalings[scaling]);
            fprintf(out, "%s %s %d %d", strategies[m], scalings[scaling], alternative->n,
                    alternative->eigen.sweeps);
            const double variance = sum(alternative->eigen.values);
            double cumulative_ratio = 0;
            for (int k = 0; k < retained; ++k) {
                fprintf(out, " %s", real(alternative->eigen.values.v[k], 4));
                cumulative_ratio += alternative->eigen.values.v[k] / variance;
            }
            fprintf(out, " %s", real(cumulative_ratio, 4));
            for (int k = 0; k < retained; ++k)
                fprintf(
                    out, " %s",
                    real(fabs(dot(row_vector(&alternative->eigen.vectors, k), row_vector(&e->vectors, k))),
                         4));
            fputc('\n', out);
            free(alternative);
        }
    fclose(out);
    FILE *loading = fopen("output/loadings.csv", "w"), *score = fopen("output/scores.csv", "w"),
         *outliers = fopen("output/outliers.txt", "w");
    fputs("variable", loading);
    for (int k = 0; k < retained; ++k)
        fprintf(loading, ",pc%d", k + 1);
    fputs(",communality", loading);
    for (int k = 0; k < retained; ++k)
        fprintf(loading, ",rc%d", k + 1);
    fputc('\n', loading);
    for (int j = 0; j < variables; ++j) {
        fputs(input.names[j], loading);
        for (int k = 0; k < retained; ++k)
            fprintf(loading, ",%s", real(loadings.v[j][k], 4));
        fprintf(loading, ",%s", real(communality.v[j], 4));
        for (int k = 0; k < retained; ++k)
            fprintf(loading, ",%s", real(rotated.v[rotated_order[k]][j], 4));
        fputc('\n', loading);
    }
    fclose(loading);
    fputs("id,set", score);
    for (int k = 0; k < retained; ++k)
        fprintf(score, ",pc%d", k + 1);
    fputc('\n', score);
    for (int set = 0; set < 2; ++set) {
        const int count = set ? input.ns : n;
        const Sample *rows = set ? input.supplementary : a->rows;
        const Diagnostic *items = set ? s : d;
        for (int i = 0; i < count; ++i) {
            fprintf(score, "%s,%s", rows[i].id, set ? "supplementary" : "data");
            for (int k = 0; k < retained; ++k)
                fprintf(score, ",%s", real(items[i].score.v[k], 4));
            fputc('\n', score);
        }
    }
    fclose(score);
    fprintf(outliers, "diagnostics components %d t2_limit %s spe_limit %s\nid t2 spe quality flag\n",
            retained, real(p->t2, 4), real(p->spe, 4));
    int tflags = 0, qflags = 0, both = 0, any = 0;
    Vector tvalues = vector(n), qvalues = vector(n);
    for (int i = 0; i < n; ++i) {
        fprintf(outliers, "%s %s %s %s %s\n", a->rows[i].id, real(d[i].t2, 4), real(d[i].spe, 4),
                real(d[i].quality, 4), d[i].flag);
        tflags += d[i].t2 > p->t2;
        qflags += d[i].spe > p->spe;
        both += strcmp(d[i].flag, "TQ") == 0;
        any += strcmp(d[i].flag, "-") != 0;
        tvalues.v[i] = d[i].t2;
        qvalues.v[i] = d[i].spe;
    }
    fprintf(outliers, "flagged t2 %d spe %d both %d any %d\n", tflags, qflags, both, any);
    for (int kind = 0; kind < 2; ++kind) {
        fprintf(outliers, "\ntop %s\nrank id %s variable contribution\n", kind ? "spe" : "t2",
                kind ? "spe" : "t2");
        const Vector values = kind ? qvalues : tvalues;
        int order[300];
        decreasing(values, order);
        for (int rank = 0; rank < p->top && rank < n; ++rank) {
            const int i = order[rank];
            const Vector contributions = kind ? d[i].qcontribution : d[i].tcontribution;
            int variable_order[300];
            decreasing(contributions, variable_order);
            const int j = variable_order[0];
            fprintf(outliers, "%d %s %s %s %s\n", rank + 1, a->rows[i].id, real(values.v[i], 4),
                    input.names[j], real(contributions.v[j], 4));
        }
    }
    fputs("\nreconstruction\nk mean_spe max_spe max_id\n", outliers);
    for (int count = 1; count < variables; ++count) {
        double total_spe = 0, maximum = -1;
        int largest = 0;
        for (int i = 0; i < n; ++i) {
            const Vector residual = residuals(d[i].z, d[i].score, &e->vectors, count);
            const double spe = dot(residual, residual);
            total_spe += spe;
            if (spe > maximum) {
                maximum = spe;
                largest = i;
            }
        }
        fprintf(outliers, "%d %s %s %s\n", count, real(total_spe / n, 4), real(maximum, 4),
                a->rows[largest].id);
    }
    fputs("\nsupplementary\nid", outliers);
    for (int k = 0; k < retained; ++k)
        fprintf(outliers, " pc%d", k + 1);
    fputs(" t2 spe flag nearest distance\n", outliers);
    for (int i = 0; i < input.ns; ++i) {
        int nearest = 0;
        double minimum = -1;
        for (int row = 0; row < n; ++row) {
            double distance = 0;
            for (int k = 0; k < retained; ++k) {
                const double delta = s[i].score.v[k] - d[row].score.v[k];
                distance += delta * delta;
            }
            if (minimum < 0 || distance < minimum) {
                minimum = distance;
                nearest = row;
            }
        }
        fputs(input.supplementary[i].id, outliers);
        for (int k = 0; k < retained; ++k)
            fprintf(outliers, " %s", real(s[i].score.v[k], 4));
        fprintf(outliers, " %s %s %s %s %s\n", real(s[i].t2, 4), real(s[i].spe, 4), s[i].flag,
                a->rows[nearest].id, real(sqrt(minimum), 4));
    }
    fclose(outliers);
    plots(&input, a, &loadings, &broken, total, average, d, s);
    free(d);
    free(s);
    free(a);
    return 0;
}
