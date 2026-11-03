#include "segments.h"

const char *feature_names[6] = {"recency", "frequency", "monetary", "basket", "categories", "tenure"};
Customers eligible_customers(const Transactions *data, Orders orders, int day) {
    int counts[400] = {0};
    for (int i = 0; i < orders.count; ++i) if (orders.items[i].net > 0) ++counts[orders.items[i].customer];
    Customers result = {.items = allocate((size_t)data->customer_count * sizeof(Customer))};
    for (int c = 0; c < data->customer_count; ++c) {
        if (!counts[c]) continue;
        Customer *customer = &result.items[result.count++];
        customer->file_number = c;
        customer->id = data->ids[c];
        customer->orders = allocate((size_t)counts[c] * sizeof(Order *));
        customer->category_spend = allocate((size_t)data->category_count * sizeof(Integer));
        customer->category_present = allocate((size_t)data->category_count * sizeof(bool));
        int first = day, last = 0;
        for (int i = 0; i < orders.count; ++i) {
            Order *order = &orders.items[i];
            if (order->customer != c || order->net <= 0) continue;
            customer->orders[customer->order_count++] = order;
            customer->spend += order->net;
            if (order->day < first) first = order->day;
            if (order->day > last) last = order->day;
            for (int r = 0; r < order->row_count; ++r) {
                const Row *row = order->rows[r];
                customer->category_spend[row->category] += row->amount;
                customer->category_present[row->category] = true;
            }
        }
        int categories = 0;
        for (int g = 0; g < data->category_count; ++g) if (customer->category_spend[g] > 0) ++categories;
        double monetary = (double)customer->spend / 100;
        customer->raw[0] = day - last; customer->raw[1] = customer->order_count;
        customer->raw[2] = monetary; customer->raw[3] = monetary / customer->order_count;
        customer->raw[4] = categories; customer->raw[5] = day - first;
        for (int f = 0; f < 6; ++f) customer->transformed[f] = f >= 1 && f <= 3 ? sqrt(customer->raw[f]) : customer->raw[f];
    }
    return result;
}
double ordered_sum(const double *values, int count) { double result = 0; for (int i = 0; i < count; ++i) result += values[i]; return result; }
Moments mean_sd(const double *values, int count) {
    double mean = ordered_sum(values, count) / count, squares = 0;
    for (int i = 0; i < count; ++i) { double difference = values[i] - mean; squares += difference * difference; }
    return (Moments){mean, count == 1 ? 0 : sqrt(squares / (count - 1))};
}
Scaling fit_scaling(Customers customers) {
    Scaling result;
    for (int f = 0; f < 6; ++f) {
        double raw[400], transformed[400];
        for (int i = 0; i < customers.count; ++i) { raw[i] = customers.items[i].raw[f]; transformed[i] = customers.items[i].transformed[f]; }
        Moments first = mean_sd(raw, customers.count), second = mean_sd(transformed, customers.count);
        result.raw_mean[f] = first.mean; result.raw_sd[f] = first.sd;
        result.mean[f] = second.mean; result.sd[f] = second.sd;
    }
    return result;
}
void standardize(Customers customers, const Scaling *scaling) {
    for (int i = 0; i < customers.count; ++i) for (int f = 0; f < 6; ++f) customers.items[i].point[f] = scaling->sd[f] == 0 ? 0 : (customers.items[i].transformed[f] - scaling->mean[f]) / scaling->sd[f];
}
double correlation(Points points, int first, int second) {
    double total = 0;
    for (int i = 0; i < points.n; ++i) total += points.v[i][first] * points.v[i][second];
    return total / (points.n - 1);
}
