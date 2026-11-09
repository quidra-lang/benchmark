#include "trainer.hpp"
static std::vector<Image> images(const std::string &path) {
    std::ifstream input(path);
    std::string text;
    std::getline(input, text);
    std::vector<Image> out;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        Image image;
        std::string label;
        std::getline(row, image.id, ',');
        std::getline(row, label, ',');
        std::getline(row, image.pixels);
        image.label = std::stoi(label);
        for (char pixel : image.pixels)
            image.input.push_back(pixel == '1' ? 1.0 : 0.0);
        out.push_back(image);
    }
    return out;
}
Input load() {
    Input out;
    std::ifstream definitions("input/network.txt");
    std::string key;
    definitions >> key >> out.width >> out.height;
    while (definitions >> key) {
        if (key == "NETWORK") {
            Network network;
            definitions >> network.name;
            network.inputs = out.width * out.height;
            out.networks.push_back(network);
        } else {
            int units;
            std::string function;
            definitions >> units >> function;
            add_layer(out.networks.back(), units, function, key == "OUTPUT");
        }
    }
    out.classes = out.networks[0].classes;
    std::ifstream weights("input/weights.txt");
    int network = 0;
    while (weights >> key) {
        if (key == "NETWORK") {
            std::string name;
            weights >> name;
            network = 0;
            while (out.networks[network].name != name)
                ++network;
        } else if (key == "LAYER") {
            int l, p, q;
            weights >> l >> p >> q;
            Network &net = out.networks[network];
            const Layer &layer = net.layers[l - 1];
            for (int j = 0; j < p; ++j) {
                weights >> key;
                for (int i = 0; i < q; ++i)
                    weights >> net.initial[layer.weights + j * q + i];
            }
            weights >> key;
            for (int j = 0; j < p; ++j)
                weights >> net.initial[layer.biases + j];
        }
    }
    out.train = images("input/train.csv");
    out.test = images("input/test.csv");
    std::ifstream settings("input/params.txt");
    std::string text;
    Params &p = out.params;
    while (std::getline(settings, text)) {
        std::istringstream row(text);
        row >> key;
        if (key == "SEED")
            row >> p.seed;
        else if (key == "BATCH_SIZE")
            row >> p.batch;
        else if (key == "MAX_EPOCHS")
            row >> p.epochs;
        else if (key == "PATIENCE")
            row >> p.patience;
        else if (key == "LR_STEP")
            row >> p.lr_step >> p.gamma;
        else if (key == "GRADIENT_CHECK_STRIDE")
            row >> p.stride;
        else if (key == "CALIBRATION_BINS")
            row >> p.bins;
        else if (key == "PRUNE" || key == "NOISE") {
            int value;
            while (row >> value)
                (key == "PRUNE" ? p.prune : p.noise).push_back(value);
        } else if (key == "RUN") {
            Run run;
            std::string name;
            row >> run.name >> name >> run.optimizer >> run.eta >> run.decay;
            run.network = 0;
            while (out.networks[run.network].name != name)
                ++run.network;
            if (run.optimizer == "MOMENTUM")
                row >> run.mu;
            else if (run.optimizer == "ADAM")
                row >> run.beta1 >> run.beta2 >> run.epsilon;
            p.runs.push_back(run);
        }
    }
    return out;
}
std::int64_t Random::draw() {
    state = 48271 * state % 2147483647;
    return state;
}
void Random::shuffle(Ids &order) {
    for (int i = int(order.size()); i >= 2; --i) {
        const int j = int(draw() % i);
        std::swap(order[i - 1], order[j]);
    }
}
