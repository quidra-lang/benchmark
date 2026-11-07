#include "analysis.hpp"
#include <filesystem>
static std::string real(double value, int precision = 4) {
    if (std::abs(value) < 0.5 * std::pow(10.0, -precision))
        value = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(precision) << value;
    return out.str();
}
static double sum(const Vector &values) {
    double out = 0;
    for (double value : values)
        out += value;
    return out;
}
static std::vector<int> decreasing(const Vector &values) {
    std::vector<int> out(values.size());
    std::iota(out.begin(), out.end(), 0);
    std::stable_sort(out.begin(), out.end(), [&](int a, int b) { return values[a] > values[b]; });
    return out;
}
static void frame(std::ostream &out, const Grid &grid) {
    for (const std::string &line : framed(grid))
        out << line << '\n';
}
struct Summary {
    int observed = 0;
    double mean = 0, sd = 0, minimum = 0, maximum = 0, msa = 0;
};
struct Analysis {
    std::vector<Sample> rows;
    Matrix values, cov, cor, matrix, z;
    Vector mean, sd, scale;
    Eigen eigen;
};
static Analysis analyze(const Input &input, const Vector &observed_means, const std::string &missing,
                        const std::string &scaling) {
    Analysis out;
    for (const Sample &row : input.data) {
        const bool complete = std::all_of(row.values.begin(), row.values.end(),
                                          [](const auto &value) { return value.has_value(); });
        if (missing == "listwise" && !complete)
            continue;
        Sample copy = row;
        Vector values;
        for (std::size_t j = 0; j < copy.values.size(); ++j) {
            if (!copy.values[j])
                copy.values[j] = observed_means[j];
            values.push_back(*copy.values[j]);
        }
        out.rows.push_back(std::move(copy));
        out.values.push_back(std::move(values));
    }
    out.mean = means(out.values);
    out.cov = covariance(out.values, out.mean);
    for (std::size_t j = 0; j < input.names.size(); ++j)
        out.sd.push_back(std::sqrt(out.cov[j][j]));
    out.cor = correlation(out.cov, out.sd);
    out.matrix = scaling == "covariance" ? out.cov : out.cor;
    out.scale = scaling == "covariance" ? Vector(input.names.size(), 1) : out.sd;
    for (const Sample &row : out.rows)
        out.z.push_back(standardize(row, out.mean, out.scale));
    out.eigen = jacobi(out.matrix);
    return out;
}
static std::string flag(double t2, double spe, const Params &p) {
    const std::string out = std::string(t2 > p.t2 ? "T" : "") + (spe > p.spe ? "Q" : "");
    return out.empty() ? "-" : out;
}
struct Diagnostic {
    Vector z, score, residual, tcontribution, qcontribution;
    double t2 = 0, spe = 0, quality = 0;
    std::string flag_;
};
static Diagnostic diagnose(const Vector &z, const Eigen &eigen, int count, const Params &p) {
    Diagnostic out;
    out.z = z;
    out.score = scores(z, eigen.vectors);
    out.residual = residuals(z, out.score, eigen.vectors, count);
    out.t2 = hotelling(out.score, eigen.values, count);
    out.spe = dot(out.residual, out.residual);
    double represented = 0;
    for (int k = 0; k < count; ++k)
        represented += out.score[k] * out.score[k];
    out.quality = represented / dot(z, z);
    out.flag_ = flag(out.t2, out.spe, p);
    for (std::size_t j = 0; j < z.size(); ++j) {
        double weight = 0;
        for (int k = 0; k < count; ++k)
            weight += (out.score[k] / eigen.values[k]) * eigen.vectors[k][j];
        out.tcontribution.push_back(z[j] * weight);
        out.qcontribution.push_back(out.residual[j] * out.residual[j]);
    }
    return out;
}
static double criterion(const Matrix &g) {
    double out = 0;
    for (std::size_t k = 0; k < g[0].size(); ++k) {
        double q2 = 0, q4 = 0;
        for (const Vector &row : g) {
            q2 += row[k] * row[k];
            q4 += (row[k] * row[k]) * (row[k] * row[k]);
        }
        out += q4 / g.size() - (q2 / g.size()) * (q2 / g.size());
    }
    return out;
}
int main() {
    std::filesystem::create_directories("output");
    const Input input = read_input();
    const Params &p = input.params;
    const int variables = input.names.size();
    std::vector<Summary> summary(variables);
    Vector observed_means(variables);
    Lines incomplete;
    for (const Sample &row : input.data)
        if (std::any_of(row.values.begin(), row.values.end(), [](const auto &value) { return !value; }))
            incomplete.push_back(row.id);
    for (int j = 0; j < variables; ++j) {
        Vector observed;
        for (const Sample &row : input.data)
            if (row.values[j])
                observed.push_back(*row.values[j]);
        Summary &s = summary[j];
        s.observed = observed.size();
        s.mean = sum(observed) / s.observed;
        observed_means[j] = s.mean;
        double squares = 0;
        for (double value : observed)
            squares += (value - s.mean) * (value - s.mean);
        s.sd = std::sqrt(squares / (s.observed - 1));
        s.minimum = *std::min_element(observed.begin(), observed.end());
        s.maximum = *std::max_element(observed.begin(), observed.end());
    }
    const Analysis analysis = analyze(input, observed_means, p.missing, p.scaling);
    const Eigen &eigen = analysis.eigen;
    const int n = analysis.rows.size();
    const double total = sum(eigen.values), average = total / variables;
    Vector ratio(variables), cumulative(variables), broken(variables), parallel(variables), errors(variables);
    int kaiser = 0, broken_count = variables, parallel_count = variables, cumulative_count = variables;
    for (int k = 0; k < variables; ++k) {
        ratio[k] = eigen.values[k] / total;
        cumulative[k] = ratio[k] + (k ? cumulative[k - 1] : 0);
        for (int i = k + 1; i <= variables; ++i)
            broken[k] += 1.0 / i;
        broken[k] /= variables;
        errors[k] = eigen.values[k] * std::sqrt(2.0 / n);
        kaiser += eigen.values[k] > average;
    }
    std::int64_t state = p.seed;
    for (int r = 0; r < p.repetitions; ++r) {
        Matrix random(n, Vector(variables));
        for (Vector &row : random)
            for (double &value : row) {
                state = (48271 * state) % 2147483647;
                value = double(state) / 2147483647;
            }
        const Matrix cov = covariance(random, means(random));
        Vector sd(variables);
        for (int j = 0; j < variables; ++j)
            sd[j] = std::sqrt(cov[j][j]);
        const Eigen result = jacobi(correlation(cov, sd));
        const double variance = sum(result.values);
        for (int k = 0; k < variables; ++k)
            parallel[k] += result.values[k] / variance;
    }
    for (double &value : parallel)
        value /= p.repetitions;
    for (int k = 0; k < variables; ++k) {
        if (broken_count == variables && ratio[k] <= broken[k])
            broken_count = k;
        if (parallel_count == variables && ratio[k] <= parallel[k])
            parallel_count = k;
        if (cumulative_count == variables && cumulative[k] >= p.cumulative)
            cumulative_count = k + 1;
    }
    int retained = 0;
    if (p.components == "kaiser")
        retained = kaiser;
    else if (p.components == "broken_stick")
        retained = broken_count;
    else if (p.components == "parallel")
        retained = parallel_count;
    else if (p.components == "cumulative")
        retained = cumulative_count;
    else
        retained = std::stoi(p.components);
    retained = std::max(1, retained);
    const auto inverse = inverse_determinant(analysis.cor);
    double rr_total = 0, pp_total = 0;
    for (int j = 0; j < variables; ++j) {
        double rr = 0, pp = 0;
        for (int k = 0; k < variables; ++k)
            if (j != k) {
                const double partial =
                    -inverse.first[j][k] / std::sqrt(inverse.first[j][j] * inverse.first[k][k]);
                rr += analysis.cor[j][k] * analysis.cor[j][k];
                pp += partial * partial;
            }
        summary[j].msa = rr / (rr + pp);
        rr_total += rr;
        pp_total += pp;
    }
    const double kmo = rr_total / (rr_total + pp_total),
                 bartlett = -(n - 1 - (2.0 * variables + 5) / 6) * std::log(inverse.second);
    Matrix loadings(variables, Vector(variables));
    Vector communality(variables);
    for (int j = 0; j < variables; ++j) {
        for (int k = 0; k < variables; ++k)
            loadings[j][k] = eigen.vectors[k][j] * std::sqrt(eigen.values[k]);
        for (int k = 0; k < retained; ++k)
            communality[j] += loadings[j][k] * loadings[j][k];
        communality[j] /= analysis.matrix[j][j];
    }
    Matrix g(variables, Vector(retained));
    Vector eta(variables);
    for (int j = 0; j < variables; ++j) {
        for (int k = 0; k < retained; ++k)
            eta[j] += loadings[j][k] * loadings[j][k];
        eta[j] = std::sqrt(eta[j]);
        for (int k = 0; k < retained; ++k)
            g[j][k] = loadings[j][k] / eta[j];
    }
    Vector criteria{criterion(g)};
    for (int cycle = 0; cycle < p.cycles; ++cycle) {
        for (int a = 0; a < retained - 1; ++a)
            for (int b = a + 1; b < retained; ++b) {
                double sa = 0, sb = 0, sc = 0, sd = 0;
                for (const Vector &row : g) {
                    const double phi = row[a] * row[a] - row[b] * row[b], psi = 2 * row[a] * row[b];
                    sa += phi;
                    sb += psi;
                    sc += phi * phi - psi * psi;
                    sd += 2 * phi * psi;
                }
                const double numerator = sd - 2 * sa * sb / variables,
                             denominator = sc - (sa * sa - sb * sb) / variables,
                             omega = std::sqrt(numerator * numerator + denominator * denominator);
                if (omega == 0)
                    continue;
                const double cos4 = denominator / omega, sin4 = numerator / omega,
                             cos2 = std::sqrt((1 + cos4) / 2), sin2 = cos2 == 0 ? 1 : sin4 / (2 * cos2),
                             cos1 = std::sqrt((1 + cos2) / 2), sin1 = sin2 / (2 * cos1);
                for (Vector &row : g) {
                    const double x = row[a], y = row[b];
                    row[a] = cos1 * x + sin1 * y;
                    row[b] = -sin1 * x + cos1 * y;
                }
            }
        criteria.push_back(criterion(g));
    }
    Matrix rotated;
    Vector rotated_ss;
    for (int k = 0; k < retained; ++k) {
        Vector vector(variables);
        for (int j = 0; j < variables; ++j)
            vector[j] = g[j][k] * eta[j];
        vector = orient(vector);
        rotated_ss.push_back(dot(vector, vector));
        rotated.push_back(std::move(vector));
    }
    const auto rotated_order = decreasing(rotated_ss);
    std::vector<Diagnostic> diagnostics, supplementary;
    for (const Vector &z : analysis.z)
        diagnostics.push_back(diagnose(z, eigen, retained, p));
    for (const Sample &row : input.supplementary)
        supplementary.push_back(
            diagnose(standardize(row, analysis.mean, analysis.scale), eigen, retained, p));
    const auto power = power_iteration(analysis.matrix, eigen.vectors);
    std::ofstream out("output/eigen.txt");
    out << "pca rows " << input.data.size() << " used " << n << " variables " << variables << " missing "
        << p.missing << " scaling " << p.scaling << '\n';
    out << "incomplete " << incomplete.size();
    if (incomplete.empty())
        out << " -";
    for (const std::string &id : incomplete)
        out << ' ' << id;
    out << "\n\nvariable observed missing mean sd min max msa\n";
    for (int j = 0; j < variables; ++j) {
        const Summary &s = summary[j];
        out << input.names[j] << ' ' << s.observed << ' ' << input.data.size() - s.observed << ' '
            << real(s.mean) << ' ' << real(s.sd) << ' ' << real(s.minimum) << ' ' << real(s.maximum) << ' '
            << real(s.msa) << '\n';
    }
    out << "adequacy kmo " << real(kmo) << " determinant " << real(inverse.second, 6) << " bartlett "
        << real(bartlett) << " df " << variables * (variables - 1) / 2 << "\n\nmatrix " << p.scaling << '\n';
    for (int j = 0; j < variables; ++j) {
        out << input.names[j];
        for (double value : analysis.matrix[j])
            out << ' ' << real(value);
        out << '\n';
    }
    struct Pair {
        int a, b;
        double magnitude;
    };
    std::vector<Pair> pairs;
    for (int j = 0; j < variables - 1; ++j)
        for (int k = j + 1; k < variables; ++k)
            pairs.push_back({j, k, std::abs(analysis.cor[j][k])});
    std::stable_sort(pairs.begin(), pairs.end(),
                     [](const Pair &a, const Pair &b) { return a.magnitude > b.magnitude; });
    out << "strongest";
    for (int i = 0; i < std::min(p.top, int(pairs.size())); ++i) {
        const Pair &pair = pairs[i];
        out << ' ' << input.names[pair.a] << ':' << input.names[pair.b] << ':'
            << real(analysis.cor[pair.a][pair.b]);
    }
    out << "\n\njacobi sweeps " << eigen.sweeps << "\neigenvalues total " << real(total) << " average "
        << real(average) << "\nk eigenvalue ratio cumulative broken_stick parallel se separated\n";
    for (int k = 0; k < variables; ++k) {
        const bool separated =
            (k == 0 || std::abs(eigen.values[k] - eigen.values[k - 1]) > errors[k]) &&
            (k + 1 == variables || std::abs(eigen.values[k] - eigen.values[k + 1]) > errors[k]);
        out << k + 1 << ' ' << real(eigen.values[k]) << ' ' << real(ratio[k]) << ' ' << real(cumulative[k])
            << ' ' << real(broken[k]) << ' ' << real(parallel[k]) << ' ' << real(errors[k]) << ' '
            << (separated ? "yes" : "no") << '\n';
    }
    out << "retention kaiser " << kaiser << " broken_stick " << broken_count << " parallel " << parallel_count
        << " cumulative " << cumulative_count << " target " << real(p.cumulative) << "\ncomponents "
        << retained << " rule " << p.components << "\n\neigenvectors\nvariable";
    for (int k = 0; k < variables; ++k)
        out << " pc" << k + 1;
    out << '\n';
    for (int j = 0; j < variables; ++j) {
        out << input.names[j];
        for (const Vector &vector : eigen.vectors)
            out << ' ' << real(vector[j]);
        out << '\n';
    }
    out << "\npower_iteration iterations 1000\nk jacobi power agree_at match\n";
    int matches = 0;
    for (int k = 0; k < variables; ++k) {
        const bool match = std::abs(power[k].value - eigen.values[k]) <= 1e-8 * eigen.values[0] &&
                           difference(power[k].vector, eigen.vectors[k]) <= 0.000001;
        matches += match;
        out << k + 1 << ' ' << real(eigen.values[k]) << ' ' << real(power[k].value) << ' '
            << (power[k].agreement ? std::to_string(power[k].agreement) : "-") << ' '
            << (match ? "yes" : "no") << '\n';
    }
    out << "cross_check " << matches << '/' << variables
        << "\n\nscores\ncomponent sd min min_id max max_id contributors\n";
    for (int k = 0; k < retained; ++k) {
        Vector contributions(n);
        double squares = 0;
        int minimum = 0, maximum = 0;
        for (int i = 0; i < n; ++i) {
            const double value = diagnostics[i].score[k];
            squares += value * value;
            contributions[i] = value * value / ((n - 1) * eigen.values[k]);
            if (value < diagnostics[minimum].score[k])
                minimum = i;
            if (value > diagnostics[maximum].score[k])
                maximum = i;
        }
        out << "pc" << k + 1 << ' ' << real(std::sqrt(squares / (n - 1))) << ' '
            << real(diagnostics[minimum].score[k]) << ' ' << analysis.rows[minimum].id << ' '
            << real(diagnostics[maximum].score[k]) << ' ' << analysis.rows[maximum].id;
        const auto order = decreasing(contributions);
        for (int i = 0; i < std::min(p.top, n); ++i)
            out << ' ' << analysis.rows[order[i]].id << ':' << real(contributions[order[i]]);
        out << '\n';
    }
    out << "\nvarimax components " << retained << " cycles " << p.cycles << '\n';
    for (std::size_t cycle = 0; cycle < criteria.size(); ++cycle)
        out << "cycle " << cycle << " criterion " << real(criteria[cycle], 6) << '\n';
    for (int k = 0; k < retained; ++k) {
        const int source = rotated_order[k];
        int closest = 0;
        double congruence = -1;
        for (int h = 0; h < retained; ++h) {
            const Vector loading = column(loadings, h);
            const double value =
                std::abs(dot(rotated[source], loading) /
                         std::sqrt(dot(rotated[source], rotated[source]) * dot(loading, loading)));
            if (value > congruence) {
                congruence = value;
                closest = h;
            }
        }
        out << "rc" << k + 1 << " ss " << real(rotated_ss[source]) << " ratio "
            << real(rotated_ss[source] / total) << " closest pc" << closest + 1 << " congruence "
            << real(congruence) << '\n';
    }
    out << "\nsensitivity\nmissing scaling rows sweeps eigenvalues cumulative congruence\n";
    for (const std::string &missing : Lines{"listwise", "mean"})
        for (const std::string &scaling : Lines{"covariance", "correlation"}) {
            const Analysis alternative = analyze(input, observed_means, missing, scaling);
            out << missing << ' ' << scaling << ' ' << alternative.rows.size() << ' '
                << alternative.eigen.sweeps;
            const double variance = sum(alternative.eigen.values);
            double cumulative_ratio = 0;
            for (int k = 0; k < retained; ++k) {
                out << ' ' << real(alternative.eigen.values[k]);
                cumulative_ratio += alternative.eigen.values[k] / variance;
            }
            out << ' ' << real(cumulative_ratio);
            for (int k = 0; k < retained; ++k)
                out << ' ' << real(std::abs(dot(alternative.eigen.vectors[k], eigen.vectors[k])));
            out << '\n';
        }
    std::ofstream loading_file("output/loadings.csv"), score_file("output/scores.csv"),
        outlier_file("output/outliers.txt"), plot_file("output/plots.txt");
    loading_file << "variable";
    for (int k = 0; k < retained; ++k)
        loading_file << ",pc" << k + 1;
    loading_file << ",communality";
    for (int k = 0; k < retained; ++k)
        loading_file << ",rc" << k + 1;
    loading_file << '\n';
    for (int j = 0; j < variables; ++j) {
        loading_file << input.names[j];
        for (int k = 0; k < retained; ++k)
            loading_file << ',' << real(loadings[j][k]);
        loading_file << ',' << real(communality[j]);
        for (int k : rotated_order)
            loading_file << ',' << real(rotated[k][j]);
        loading_file << '\n';
    }
    score_file << "id,set";
    for (int k = 0; k < retained; ++k)
        score_file << ",pc" << k + 1;
    score_file << '\n';
    for (int set = 0; set < 2; ++set) {
        const auto &rows = set ? input.supplementary : analysis.rows;
        const auto &items = set ? supplementary : diagnostics;
        for (std::size_t i = 0; i < rows.size(); ++i) {
            score_file << rows[i].id << ',' << (set ? "supplementary" : "data");
            for (int k = 0; k < retained; ++k)
                score_file << ',' << real(items[i].score[k]);
            score_file << '\n';
        }
    }
    outlier_file << "diagnostics components " << retained << " t2_limit " << real(p.t2) << " spe_limit "
                 << real(p.spe) << "\nid t2 spe quality flag\n";
    int tflags = 0, qflags = 0, both = 0, any = 0;
    Vector tvalues, qvalues;
    for (int i = 0; i < n; ++i) {
        const Diagnostic &d = diagnostics[i];
        outlier_file << analysis.rows[i].id << ' ' << real(d.t2) << ' ' << real(d.spe) << ' '
                     << real(d.quality) << ' ' << d.flag_ << '\n';
        tflags += d.t2 > p.t2;
        qflags += d.spe > p.spe;
        both += d.flag_ == "TQ";
        any += d.flag_ != "-";
        tvalues.push_back(d.t2);
        qvalues.push_back(d.spe);
    }
    outlier_file << "flagged t2 " << tflags << " spe " << qflags << " both " << both << " any " << any
                 << '\n';
    for (int kind = 0; kind < 2; ++kind) {
        outlier_file << "\ntop " << (kind ? "spe" : "t2") << "\nrank id " << (kind ? "spe" : "t2")
                     << " variable contribution\n";
        const Vector &values = kind ? qvalues : tvalues;
        const auto order = decreasing(values);
        for (int rank = 0; rank < std::min(p.top, n); ++rank) {
            const int i = order[rank];
            const Vector &contributions = kind ? diagnostics[i].qcontribution : diagnostics[i].tcontribution;
            const int j = decreasing(contributions)[0];
            outlier_file << rank + 1 << ' ' << analysis.rows[i].id << ' ' << real(values[i]) << ' '
                         << input.names[j] << ' ' << real(contributions[j]) << '\n';
        }
    }
    outlier_file << "\nreconstruction\nk mean_spe max_spe max_id\n";
    for (int count = 1; count < variables; ++count) {
        double total_spe = 0, maximum = -1;
        int largest = 0;
        for (int i = 0; i < n; ++i) {
            const Vector e = residuals(analysis.z[i], diagnostics[i].score, eigen.vectors, count);
            const double spe = dot(e, e);
            total_spe += spe;
            if (spe > maximum) {
                maximum = spe;
                largest = i;
            }
        }
        outlier_file << count << ' ' << real(total_spe / n) << ' ' << real(maximum) << ' '
                     << analysis.rows[largest].id << '\n';
    }
    outlier_file << "\nsupplementary\nid";
    for (int k = 0; k < retained; ++k)
        outlier_file << " pc" << k + 1;
    outlier_file << " t2 spe flag nearest distance\n";
    for (std::size_t i = 0; i < supplementary.size(); ++i) {
        const Diagnostic &d = supplementary[i];
        int nearest = 0;
        double minimum = -1;
        for (int row = 0; row < n; ++row) {
            double distance = 0;
            for (int k = 0; k < retained; ++k) {
                const double delta = d.score[k] - diagnostics[row].score[k];
                distance += delta * delta;
            }
            if (minimum < 0 || distance < minimum) {
                minimum = distance;
                nearest = row;
            }
        }
        outlier_file << input.supplementary[i].id;
        for (int k = 0; k < retained; ++k)
            outlier_file << ' ' << real(d.score[k]);
        outlier_file << ' ' << real(d.t2) << ' ' << real(d.spe) << ' ' << d.flag_ << ' '
                     << analysis.rows[nearest].id << ' ' << real(std::sqrt(minimum)) << '\n';
    }
    const int kc = int(std::floor(average / eigen.values[0] * p.scree + 0.5));
    plot_file << "scree width " << p.scree << " kaiser_column " << kc << '\n';
    for (int k = 0; k < variables; ++k) {
        const int length = int(std::floor(eigen.values[k] / eigen.values[0] * p.scree + 0.5)),
                  position = int(std::floor(broken[k] * total / eigen.values[0] * p.scree + 0.5));
        plot_file << scree_line(length, kc, position, p.scree) << " pc" << k + 1 << ' '
                  << real(eigen.values[k]) << '\n';
    }
    double m1 = 0, m2 = 0, l1 = 0, l2 = 0;
    for (const auto &items : {diagnostics, supplementary})
        for (const Diagnostic &d : items) {
            m1 = std::max(m1, std::abs(d.score[0]));
            m2 = std::max(m2, std::abs(d.score[1]));
        }
    for (const Vector &row : loadings) {
        l1 = std::max(l1, std::abs(row[0]));
        l2 = std::max(l2, std::abs(row[1]));
    }
    const double scale = 0.9 * std::min(m1 / l1, m2 / l2);
    Grid biplot = grid(p.bh, p.bw);
    const Cell origin = biplot_cell(0, 0, m1, m2, p.bw, p.bh);
    std::fill(biplot[origin.first].begin(), biplot[origin.first].end(), '-');
    for (std::string &row : biplot)
        row[origin.second] = '|';
    biplot[origin.first][origin.second] = '+';
    std::vector<Cell> tips;
    for (int j = 0; j < variables; ++j) {
        const Cell tip = biplot_cell(scale * loadings[j][0], scale * loadings[j][1], m1, m2, p.bw, p.bh);
        tips.push_back(tip);
        for (Cell cell : shaft_cells(origin, tip))
            biplot[cell.first][cell.second] = shaft_character(origin, tip);
    }
    std::vector<std::vector<int>> counts(p.bh, std::vector<int>(p.bw));
    for (const Diagnostic &d : diagnostics) {
        const Cell cell = biplot_cell(d.score[0], d.score[1], m1, m2, p.bw, p.bh);
        ++counts[cell.first][cell.second];
    }
    for (int r = 0; r < p.bh; ++r)
        for (int c = 0; c < p.bw; ++c)
            if (counts[r][c])
                biplot[r][c] = counts[r][c] == 1 ? '.' : counts[r][c] <= 3 ? 'o' : '@';
    for (const Diagnostic &d : diagnostics)
        if (d.flag_ != "-") {
            const Cell cell = biplot_cell(d.score[0], d.score[1], m1, m2, p.bw, p.bh);
            biplot[cell.first][cell.second] = 'X';
        }
    for (const Diagnostic &d : supplementary) {
        const Cell cell = biplot_cell(d.score[0], d.score[1], m1, m2, p.bw, p.bh);
        biplot[cell.first][cell.second] = '*';
    }
    for (int j = 0; j < variables; ++j)
        biplot[tips[j].first][tips[j].second] = char('A' + j);
    plot_file << "\nbiplot pc1 pc2 width " << p.bw << " height " << p.bh << "\nx " << real(-m1) << ' '
              << real(m1) << " y " << real(-m2) << ' ' << real(m2) << " arrow_scale " << real(scale) << '\n';
    frame(plot_file, biplot);
    for (int j = 0; j < variables; ++j)
        plot_file << char('A' + j) << ' ' << input.names[j] << ' ' << real(loadings[j][0]) << ' '
                  << real(loadings[j][1]) << '\n';
    const int rho = p.radius, rc = rho / 2 + 1, cc = rho + 1;
    Grid circle = grid(rho + 3, 2 * rho + 3);
    std::fill(circle[rc].begin(), circle[rc].end(), '-');
    for (std::string &row : circle)
        row[cc] = '|';
    circle[rc][cc] = '+';
    auto inside = [&](int r, int c) {
        return (c - cc) * (c - cc) + (2 * (r - rc)) * (2 * (r - rc)) <= rho * rho;
    };
    for (int r = 0; r < int(circle.size()); ++r)
        for (int c = 0; c < int(circle[0].size()); ++c)
            if (inside(r, c) &&
                (!inside(r - 1, c) || !inside(r + 1, c) || !inside(r, c - 1) || !inside(r, c + 1)))
                circle[r][c] = '.';
    for (int j = 0; j < variables; ++j) {
        const double q1 = loadings[j][0] / std::sqrt(analysis.matrix[j][j]),
                     q2 = loadings[j][1] / std::sqrt(analysis.matrix[j][j]);
        const Cell cell = circle_cell(q1, q2, rho);
        circle[cell.first][cell.second] = char('A' + j);
    }
    plot_file << "\ncircle radius " << rho << '\n';
    frame(plot_file, circle);
    for (int j = 0; j < variables; ++j) {
        const double q1 = loadings[j][0] / std::sqrt(analysis.matrix[j][j]),
                     q2 = loadings[j][1] / std::sqrt(analysis.matrix[j][j]);
        plot_file << char('A' + j) << ' ' << input.names[j] << ' ' << real(q1) << ' ' << real(q2) << ' '
                  << real(q1 * q1 + q2 * q2) << '\n';
    }
    Grid diagnostic_plot = grid(p.dh, p.dw);
    const Cell limit = diagnostic_cell(p.t2, p.spe, 2 * p.t2, 2 * p.spe, p.dw, p.dh);
    std::fill(diagnostic_plot[limit.first].begin(), diagnostic_plot[limit.first].end(), '-');
    for (std::string &row : diagnostic_plot)
        row[limit.second] = '|';
    diagnostic_plot[limit.first][limit.second] = '+';
    counts = std::vector<std::vector<int>>(p.dh, std::vector<int>(p.dw));
    for (const Diagnostic &d : diagnostics) {
        const Cell cell = diagnostic_cell(d.t2, d.spe, 2 * p.t2, 2 * p.spe, p.dw, p.dh);
        ++counts[cell.first][cell.second];
    }
    for (int r = 0; r < p.dh; ++r)
        for (int c = 0; c < p.dw; ++c)
            if (counts[r][c])
                diagnostic_plot[r][c] = counts[r][c] == 1 ? '.' : counts[r][c] <= 3 ? 'o' : '@';
    for (const Diagnostic &d : supplementary) {
        const Cell cell = diagnostic_cell(d.t2, d.spe, 2 * p.t2, 2 * p.spe, p.dw, p.dh);
        diagnostic_plot[cell.first][cell.second] = '*';
    }
    plot_file << "\ndiagnostic width " << p.dw << " height " << p.dh << " t2_max " << real(2 * p.t2)
              << " spe_max " << real(2 * p.spe) << '\n';
    frame(plot_file, diagnostic_plot);
}
