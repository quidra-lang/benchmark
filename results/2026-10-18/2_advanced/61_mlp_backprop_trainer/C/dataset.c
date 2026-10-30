#include "trainer.h"
static int images(const char *path, Image *out) {
    Lines lines = read_lines(path);
    int count = 0;
    for (int i = 1; i < lines.count; ++i) {
        Image *image = &out[count++];
        sscanf(lines.data[i], "%8[^,],%d,%64s", image->id, &image->label, image->pixels);
        for (int p = 0; image->pixels[p]; ++p)
            image->input[p] = image->pixels[p] == '1' ? 1 : 0;
    }
    return count;
}
Input *load(void) {
    Input *out = allocate(1, sizeof(Input));
    Lines definitions = read_lines("input/network.txt");
    sscanf(definitions.data[0], "IMAGE %d %d", &out->width, &out->height);
    for (int i = 1; i < definitions.count; ++i) {
        if (!*definitions.data[i])
            continue;
        char key[10];
        sscanf(definitions.data[i], "%9s", key);
        if (strcmp(key, "NETWORK") == 0) {
            Network *network = &out->networks[out->network_count++];
            sscanf(definitions.data[i], "NETWORK %16s", network->name);
            network->inputs = out->width * out->height;
        } else {
            int units;
            char function[8];
            sscanf(definitions.data[i], "%*s %d %7s", &units, function);
            add_layer(&out->networks[out->network_count - 1], units, function,
                      strcmp(key, "OUTPUT") == 0);
        }
    }
    out->classes = out->networks[0].classes;
    FILE *weights = fopen("input/weights.txt", "r");
    char key[32];
    int current = 0;
    while (fscanf(weights, "%31s", key) == 1) {
        if (strcmp(key, "NETWORK") == 0) {
            char name[17];
            fscanf(weights, "%16s", name);
            current = 0;
            while (strcmp(out->networks[current].name, name))
                ++current;
        } else if (strcmp(key, "LAYER") == 0) {
            int l, p, q;
            fscanf(weights, "%d %d %d", &l, &p, &q);
            Network *network = &out->networks[current];
            Layer layer = network->layers[l - 1];
            for (int j = 0; j < p; ++j) {
                fscanf(weights, "%31s", key);
                for (int i = 0; i < q; ++i)
                    fscanf(weights, "%lf", &network->initial[layer.weights + j * q + i]);
            }
            fscanf(weights, "%31s", key);
            for (int j = 0; j < p; ++j)
                fscanf(weights, "%lf", &network->initial[layer.biases + j]);
        }
    }
    fclose(weights);
    out->train_count = images("input/train.csv", out->train);
    out->test_count = images("input/test.csv", out->test);
    Lines settings = read_lines("input/params.txt");
    Params *p = &out->params;
    for (int i = 0; i < settings.count; ++i) {
        sscanf(settings.data[i], "%31s", key);
        const char *value = settings.data[i] + strlen(key) + 1;
        if (strcmp(key, "SEED") == 0) {
            long long seed;
            sscanf(value, "%lld", &seed);
            p->seed = (int64_t)seed;
        } else if (strcmp(key, "BATCH_SIZE") == 0)
            sscanf(value, "%d", &p->batch);
        else if (strcmp(key, "MAX_EPOCHS") == 0)
            sscanf(value, "%d", &p->epochs);
        else if (strcmp(key, "PATIENCE") == 0)
            sscanf(value, "%d", &p->patience);
        else if (strcmp(key, "LR_STEP") == 0)
            sscanf(value, "%d %lf", &p->lr_step, &p->gamma);
        else if (strcmp(key, "GRADIENT_CHECK_STRIDE") == 0)
            sscanf(value, "%d", &p->stride);
        else if (strcmp(key, "CALIBRATION_BINS") == 0)
            sscanf(value, "%d", &p->bins);
        else if (strcmp(key, "PRUNE") == 0 || strcmp(key, "NOISE") == 0) {
            int offset = 0, used, number;
            while (sscanf(value + offset, "%d %n", &number, &used) == 1) {
                if (strcmp(key, "PRUNE") == 0)
                    p->prune[p->prune_count++] = number;
                else
                    p->noise[p->noise_count++] = number;
                offset += used;
            }
        } else if (strcmp(key, "RUN") == 0) {
            Run *run = &p->runs[p->run_count++];
            char name[17];
            int offset = 0;
            sscanf(value, "%20s %16s %8s %lf %lf %n", run->name, name, run->optimizer, &run->eta,
                   &run->decay, &offset);
            while (strcmp(out->networks[run->network].name, name))
                ++run->network;
            if (strcmp(run->optimizer, "MOMENTUM") == 0)
                sscanf(value + offset, "%lf", &run->mu);
            else if (strcmp(run->optimizer, "ADAM") == 0)
                sscanf(value + offset, "%lf %lf %lf", &run->beta1, &run->beta2, &run->epsilon);
        }
    }
    return out;
}
int64_t random_draw(Random *random) {
    random->state = 48271 * random->state % 2147483647;
    return random->state;
}
void shuffle(Random *random, int *order, int count) {
    for (int i = count; i >= 2; --i) {
        int j = (int)(random_draw(random) % i), value = order[i - 1];
        order[i - 1] = order[j];
        order[j] = value;
    }
}
