#include "archive.h"
enum { TOP = 65535, HALF = 32768, QUARTER = 16384, THREE = 49152 };
typedef struct {
    Integer frequency[257], total;
} Context;
typedef struct {
    Context *tables[256];
    int contexts, rescales;
} Contexts;
static Context *context_table(Contexts *contexts, int index) {
    if (!contexts->tables[index]) {
        Context *table = resize(NULL, sizeof(Context));
        for (int i = 0; i < 257; ++i)
            table->frequency[i] = 1;
        table->total = 257;
        contexts->tables[index] = table;
        ++contexts->contexts;
    }
    return contexts->tables[index];
}
static void dispose(Contexts *contexts) {
    for (int i = 0; i < 256; ++i)
        free(contexts->tables[i]);
}
static void update(Contexts *contexts, Context *table, int symbol) {
    table->frequency[symbol] += 32;
    table->total += 32;
    if (table->total >= 8192) {
        table->total = 0;
        for (int i = 0; i < 257; ++i) {
            table->frequency[i] = (table->frequency[i] + 1) / 2;
            table->total += table->frequency[i];
        }
        ++contexts->rescales;
    }
}
static Integer cumulative(const Context *table, int symbol) {
    Integer sum = 0;
    for (int i = 0; i < symbol; ++i)
        sum += table->frequency[i];
    return sum;
}
static void emit(BitWriter *writer, int bit, Integer *follow) {
    bit_write(writer, (uint32_t)bit, 1);
    while (*follow) {
        bit_write(writer, (uint32_t)(1 - bit), 1);
        --*follow;
    }
}
Bytes arith_encode(const Bytes *data, ArithStats *stats) {
    Contexts contexts = {0};
    BitWriter writer = {0};
    Integer low = 0, high = TOP, follow = 0;
    int context = 10;
    for (size_t i = 0; i <= data->count; ++i) {
        int symbol = i == data->count ? 256 : data->data[i];
        Context *table = context_table(&contexts, context);
        Integer range = high - low + 1, total = cumulative(table, symbol), old = low;
        high = old + range * (total + table->frequency[symbol]) / table->total - 1;
        low = old + range * total / table->total;
        while (true) {
            if (high < HALF)
                emit(&writer, 0, &follow);
            else if (low >= HALF) {
                emit(&writer, 1, &follow);
                low -= HALF;
                high -= HALF;
            } else if (low >= QUARTER && high < THREE) {
                ++follow;
                low -= QUARTER;
                high -= QUARTER;
            } else
                break;
            low *= 2;
            high = 2 * high + 1;
        }
        if (symbol != 256) {
            update(&contexts, table, symbol);
            context = symbol;
        }
    }
    ++follow;
    emit(&writer, low < QUARTER ? 0 : 1, &follow);
    stats->bits = (int)writer.count;
    stats->contexts = contexts.contexts;
    stats->rescales = contexts.rescales;
    dispose(&contexts);
    return writer.bytes;
}
const char *arith_decode(const Bytes *payload, uint32_t size, Bytes *output) {
    Contexts contexts = {0};
    BitReader reader = {.bytes = payload, .zero_extend = true};
    Integer low = 0, high = TOP, value = bit_read(&reader, 16);
    int context = 10;
    const char *error = NULL;
    while (true) {
        Context *table = context_table(&contexts, context);
        Integer range = high - low + 1, q = ((value - low + 1) * table->total - 1) / range, total = 0;
        int symbol = 0;
        while (total + table->frequency[symbol] <= q)
            total += table->frequency[symbol++];
        Integer old = low;
        high = old + range * (total + table->frequency[symbol]) / table->total - 1;
        low = old + range * total / table->total;
        while (true) {
            if (high < HALF) {
            } else if (low >= HALF) {
                low -= HALF;
                high -= HALF;
                value -= HALF;
            } else if (low >= QUARTER && high < THREE) {
                low -= QUARTER;
                high -= QUARTER;
                value -= QUARTER;
            } else
                break;
            low *= 2;
            high = 2 * high + 1;
            value = 2 * value + bit_read(&reader, 1);
        }
        if (symbol == 256) {
            if (output->count < size)
                error = "early_end";
            break;
        }
        if (output->count == size) {
            error = "overrun";
            break;
        }
        byte_push(output, (Byte)symbol);
        update(&contexts, table, symbol);
        context = symbol;
    }
    dispose(&contexts);
    return error;
}
