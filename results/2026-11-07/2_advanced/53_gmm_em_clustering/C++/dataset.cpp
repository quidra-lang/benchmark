#include "mixture.hpp"
const char *type_name(Type type) {
    static const char *names[] = {"FULL", "TIED", "DIAG", "SPHERICAL"};
    return names[int(type)];
}
static Type parse_type(const std::string &name) {
    for (Type type : {Type::FULL, Type::TIED, Type::DIAG, Type::SPHERICAL})
        if (name == type_name(type))
            return type;
    return Type::FULL;
}
Input load() {
    Input out;
    std::ifstream points("input/points.csv");
    std::string line;
    std::getline(points, line);
    while (std::getline(points, line)) {
        std::replace(line.begin(), line.end(), ',', ' ');
        std::istringstream fields(line);
        Point point;
        fields >> point.id >> point.xy[0] >> point.xy[1];
        out.points.push_back(point);
    }
    std::ifstream settings("input/params.txt");
    Params &p = out.params;
    std::getline(settings, line);
    std::istringstream ks(line);
    std::string key, name;
    ks >> key;
    int k;
    while (ks >> k)
        p.ks.push_back(k);
    settings >> key >> p.iterations;
    std::getline(settings, line);
    std::getline(settings, line);
    std::istringstream types(line);
    types >> key;
    while (types >> name)
        p.types.push_back(parse_type(name));
    settings >> key >> p.epsilon >> key >> p.tolerance >> key >> p.kmeans_max >> key >> p.folds >> key >>
        p.uncertain >> key >> p.low_density;
    std::getline(settings, line);
    std::getline(settings, line);
    std::istringstream boundaries(line);
    boundaries >> key;
    double value;
    while (boundaries >> value)
        p.gof.push_back(value);
    settings >> key >> p.xmin >> p.xmax >> key >> p.ymin >> p.ymax >> key >> p.width >> p.height;
    std::ifstream initials("input/init.txt");
    while (initials >> key >> k) {
        Model model;
        model.components.resize(k);
        initials >> key;
        for (auto &component : model.components)
            initials >> component.weight;
        for (auto &component : model.components) {
            int number;
            initials >> key >> number >> component.mean[0] >> component.mean[1] >> component.cov[0] >>
                component.cov[1] >> component.cov[2];
        }
        if (k >= 1 && k <= 4)
            out.initial[k] = std::move(model);
    }
    return out;
}
