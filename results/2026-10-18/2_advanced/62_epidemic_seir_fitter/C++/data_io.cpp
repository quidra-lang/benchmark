#include "epidemic.hpp"
#include <filesystem>
Input load() {
    Input out;
    std::ifstream cases("input/cases.csv");
    std::string text;
    std::getline(cases, text);
    while (std::getline(cases, text)) {
        std::replace(text.begin(), text.end(), ',', ' ');
        std::istringstream row(text);
        int day;
        I c, q;
        row >> day >> c >> q;
        out.cases.push_back(c);
        out.deaths.push_back(q);
    }
    std::ifstream population("input/population.txt");
    while (std::getline(population, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "group") {
            Group group;
            row >> group.name >> group.population >> group.fatality;
            out.groups.push_back(group);
        } else {
            Field values;
            double value;
            while (row >> value)
                values.push_back(value);
            out.contacts.push_back(values);
        }
    }
    std::ifstream interventions("input/interventions.txt");
    Intervention item;
    while (interventions >> item.day >> item.multiplier)
        out.interventions.push_back(item);
    std::ifstream settings("input/params.txt");
    Params &p = out.params;
    while (std::getline(settings, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "sigma")
            row >> p.sigma;
        else if (key == "gamma")
            row >> p.gamma;
        else if (key == "initial")
            row >> p.e0 >> p.i0;
        else if (key == "beta_grid")
            row >> p.beta_min >> p.beta_max >> p.beta_count;
        else if (key == "rho_grid")
            row >> p.rho_min >> p.rho_max >> p.rho_count;
        else if (key == "golden")
            row >> p.golden >> p.rounds;
        else if (key == "simplex")
            row >> p.delta_beta >> p.delta_gamma;
        else if (key == "nelder_mead")
            row >> p.alpha >> p.chi >> p.psi >> p.omega >> p.nelder;
        else if (key == "holdout")
            row >> p.holdout;
        else if (key == "effect_width")
            row >> p.effect_width;
        else if (key == "outlier")
            row >> p.outlier;
        else if (key == "death_lag")
            row >> p.death_lag;
        else if (key == "milestones") {
            I target;
            while (row >> target)
                p.milestones.push_back(target);
        } else if (key == "generation")
            row >> p.generation;
        else if (key == "horizon")
            row >> p.horizon;
        else if (key == "threshold")
            row >> p.threshold;
        else if (key == "scenario") {
            Scenario s;
            row >> s.name >> s.multiplier;
            p.scenarios.push_back(s);
        } else if (key == "contact_change") {
            ContactChange change;
            row >> change.name >> change.group >> change.factor;
            p.changes.push_back(change);
        }
    }
    return out;
}
void save(const std::string &name, const Lines &lines) {
    std::filesystem::create_directories("output");
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
