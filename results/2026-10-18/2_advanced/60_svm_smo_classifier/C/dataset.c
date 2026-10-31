#include "classifier.h"
static int read_data(const char *path, Example *data) {
    Lines lines = read_lines(path);
    int count = 0;
    for (int i = 1; i < lines.count; ++i) {
        Example *example = &data[count++];
        sscanf(lines.data[i], "%8[^,],%lf,%lf,%d", example->id, &example->point[0],
               &example->point[1], &example->label);
    }
    return count;
}
Input *load(void) {
    Input *out = allocate(1, sizeof(Input));
    out->train_count = read_data("input/train.csv", out->train);
    out->test_count = read_data("input/test.csv", out->test);
    Lines multi = read_lines("input/multiclass.csv");
    for (int i = 1; i < multi.count; ++i) {
        Example example;
        char role[6];
        sscanf(multi.data[i], "%8[^,],%lf,%lf,%d,%5s", example.id, &example.point[0],
               &example.point[1], &example.label, role);
        if (strcmp(role, "train") == 0)
            out->multi_train[out->multi_train_count++] = example;
        else
            out->multi_test[out->multi_test_count++] = example;
    }
    Lines settings = read_lines("input/params.txt");
    Params *p = &out->params;
    for (int i = 0; i < settings.count; ++i) {
        char key[20];
        sscanf(settings.data[i], "%19s", key);
        const char *value = settings.data[i] + strlen(key) + 1;
        if (strcmp(key, "C_GRID") == 0) {
            int offset = 0, used;
            double c;
            while (sscanf(value + offset, "%lf %n", &c, &used) == 1) {
                p->c_grid[p->c_count++] = c;
                offset += used;
            }
        } else if (strcmp(key, "KERNEL") == 0) {
            Kernel *kernel = &p->kernels[p->kernel_count++];
            sscanf(value, "%8s %6s", kernel->name, kernel->kind);
            kernel->degree = 1;
            if (strcmp(kernel->kind, "poly") == 0)
                sscanf(value, "%*s %*s %d %lf %lf", &kernel->degree, &kernel->gamma,
                       &kernel->coef0);
            else if (strcmp(kernel->kind, "rbf") == 0)
                sscanf(value, "%*s %*s %lf", &kernel->gamma);
        } else if (strcmp(key, "TOLERANCE") == 0)
            sscanf(value, "%lf", &p->tolerance);
        else if (strcmp(key, "EPS") == 0)
            sscanf(value, "%lf", &p->epsilon);
        else if (strcmp(key, "MAX_PASSES") == 0)
            sscanf(value, "%d", &p->max_passes);
        else if (strcmp(key, "FOLDS") == 0)
            sscanf(value, "%d", &p->folds);
        else if (strcmp(key, "LEARNING_CURVE") == 0) {
            int offset = 0, used, q;
            while (sscanf(value + offset, "%d %n", &q, &used) == 1) {
                p->learning[p->learning_count++] = q;
                offset += used;
            }
        } else if (strcmp(key, "NEWTON_ITERATIONS") == 0)
            sscanf(value, "%d", &p->newton_iterations);
        else if (strcmp(key, "MULTICLASS") == 0)
            sscanf(value, "%8s %lf", p->multi_name, &p->multi_c);
        else if (strcmp(key, "PEGASOS") == 0) {
            long long seed;
            sscanf(value, "%lf %d %lld", &p->lambda, &p->pegasos_iterations, &seed);
            p->seed = (int64_t)seed;
        } else if (strcmp(key, "PLOT_X") == 0)
            sscanf(value, "%lf %lf", &p->x_min, &p->x_max);
        else if (strcmp(key, "PLOT_Y") == 0)
            sscanf(value, "%lf %lf", &p->y_min, &p->y_max);
        else if (strcmp(key, "PLOT_SIZE") == 0)
            sscanf(value, "%d %d", &p->width, &p->height);
    }
    return out;
}
