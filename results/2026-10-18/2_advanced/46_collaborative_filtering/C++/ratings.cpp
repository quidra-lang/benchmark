#include "recommender.hpp"
static Lines split(const std::string &text, char delimiter) {
    Lines out;
    std::istringstream stream(text);
    std::string field;
    while (std::getline(stream, field, delimiter))
        out.push_back(field);
    return out;
}
static std::vector<Rating> ratings(const std::string &path, bool times) {
    std::ifstream file(path);
    std::string line;
    std::getline(file, line);
    std::vector<Rating> out;
    while (std::getline(file, line)) {
        const Lines fields = split(line, ',');
        out.push_back({std::stoi(fields[0]), std::stoi(fields[1]), std::stoi(fields[2]),
                       times ? std::stoll(fields[3]) : 0});
    }
    return out;
}
Data read_input() {
    Data out;
    out.train = ratings("input/ratings.csv", true);
    out.test = ratings("input/test.csv", false);
    std::ifstream items("input/items.csv");
    std::string line;
    std::getline(items, line);
    std::map<int, Item> catalog;
    while (std::getline(items, line)) {
        const Lines fields = split(line, ',');
        Item item{std::stoi(fields[0]), fields[1], fields[2], split(fields[2], '|')};
        catalog.emplace(item.id, item);
        out.catalog.push_back(std::move(item));
    }
    std::set<int> users, ids;
    for (const Rating &r : out.train) {
        users.insert(r.user);
        ids.insert(r.item);
    }
    out.users.assign(users.begin(), users.end());
    for (int id : ids)
        out.items.push_back(catalog.at(id));
    std::map<int, int> ui, ii;
    for (std::size_t u = 0; u < out.users.size(); ++u)
        ui[out.users[u]] = u;
    for (std::size_t i = 0; i < out.items.size(); ++i)
        ii[out.items[i].id] = i;
    out.user_count.resize(users.size());
    out.item_count.resize(ids.size());
    out.user_sum.resize(users.size());
    out.item_sum.resize(ids.size());
    out.ratings = std::vector<Ints>(users.size(), Ints(ids.size()));
    int total = 0;
    for (Rating &r : out.train) {
        r.user = ui.at(r.user);
        r.item = ii.at(r.item);
        out.ratings[r.user][r.item] = r.rating;
        ++out.user_count[r.user];
        ++out.item_count[r.item];
        out.user_sum[r.user] += r.rating;
        out.item_sum[r.item] += r.rating;
        total += r.rating;
    }
    for (Rating &r : out.test) {
        r.user = ui.at(r.user);
        r.item = ii.at(r.item);
    }
    out.mean = double(total) / out.train.size();
    for (std::size_t u = 0; u < users.size(); ++u)
        out.user_mean.push_back(double(out.user_sum[u]) / out.user_count[u]);
    for (std::size_t i = 0; i < ids.size(); ++i)
        out.item_mean.push_back(double(out.item_sum[i]) / out.item_count[i]);
    std::ifstream params("input/params.txt");
    Params &p = out.params;
    while (std::getline(params, line)) {
        std::istringstream fields(line);
        std::string key;
        fields >> key;
        if (key == "NEIGHBORS")
            fields >> p.neighbors;
        else if (key == "SHRINKAGE")
            fields >> p.shrinkage;
        else if (key == "MIN_SIMILARITY")
            fields >> p.minimum;
        else if (key == "BIAS_REG")
            fields >> p.item_reg >> p.user_reg;
        else if (key == "FACTORS")
            fields >> p.factors;
        else if (key == "LEARNING_RATE")
            fields >> p.rate;
        else if (key == "REGULARIZATION")
            fields >> p.regularization;
        else if (key == "EPOCHS")
            fields >> p.epochs;
        else if (key == "ALS_REG")
            fields >> p.als_reg;
        else if (key == "ALS_ITERATIONS")
            fields >> p.iterations;
        else if (key == "SEED")
            fields >> p.seed;
        else if (key == "TOP_N")
            fields >> p.top;
        else if (key == "TIME_BUCKETS")
            fields >> p.buckets;
        else if (key == "LIST_SIZE")
            fields >> p.list;
        else {
            Ints *values = key == "CUTOFFS"           ? &p.cutoffs
                           : key == "NEIGHBOR_GRID"   ? &p.grid
                           : key == "USER_GROUPS"     ? &p.user_groups
                           : key == "ITEM_GROUPS"     ? &p.item_groups
                           : key == "RECOMMEND_USERS" ? &p.users
                                                      : &p.items;
            int value;
            while (fields >> value)
                values->push_back(value);
        }
    }
    return out;
}
