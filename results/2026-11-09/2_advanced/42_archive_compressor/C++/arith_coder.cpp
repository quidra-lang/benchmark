#include "archive.hpp"
namespace {
constexpr Integer top = 65535, half = 32768, quarter = 16384, three = 49152;
struct Context {
    std::array<Integer, 257> frequency;
    Integer total = 257;
    Context() {
        frequency.fill(1);
    }
    void update(int symbol, int &rescales) {
        frequency[symbol] += 32;
        total += 32;
        if (total >= 8192) {
            total = 0;
            for (Integer &value : frequency) {
                value = (value + 1) / 2;
                total += value;
            }
            ++rescales;
        }
    }
    Integer cumulative(int symbol) const {
        Integer sum = 0;
        for (int i = 0; i < symbol; ++i)
            sum += frequency[i];
        return sum;
    }
};
}
Bytes arith_encode(const Bytes &data, ArithStats &stats) {
    std::map<int, Context> contexts;
    BitWriter writer;
    Integer low = 0, high = top, follow = 0;
    int context = 10;
    auto emit = [&](int bit) {
        writer.write(bit, 1);
        while (follow) {
            writer.write(1 - bit, 1);
            --follow;
        }
    };
    for (std::size_t i = 0; i <= data.size(); ++i) {
        const int symbol = i == data.size() ? 256 : data[i];
        Context &table = contexts[context];
        const Integer range = high - low + 1, cumulative = table.cumulative(symbol), old = low;
        high = old + range * (cumulative + table.frequency[symbol]) / table.total - 1;
        low = old + range * cumulative / table.total;
        while (true) {
            if (high < half)
                emit(0);
            else if (low >= half) {
                emit(1);
                low -= half;
                high -= half;
            } else if (low >= quarter && high < three) {
                ++follow;
                low -= quarter;
                high -= quarter;
            } else
                break;
            low *= 2;
            high = 2 * high + 1;
        }
        if (symbol != 256) {
            table.update(symbol, stats.rescales);
            context = symbol;
        }
    }
    ++follow;
    emit(low < quarter ? 0 : 1);
    stats.bits = writer.count;
    stats.contexts = contexts.size();
    return writer.bytes;
}
void arith_decode(const Bytes &payload, std::uint32_t size, Bytes &output) {
    std::map<int, Context> contexts;
    BitReader reader{payload, 0, true};
    Integer low = 0, high = top, value = reader.read(16);
    int context = 10, rescales = 0;
    while (true) {
        Context &table = contexts[context];
        const Integer range = high - low + 1, q = ((value - low + 1) * table.total - 1) / range;
        int symbol = 0;
        Integer cumulative = 0;
        while (cumulative + table.frequency[symbol] <= q)
            cumulative += table.frequency[symbol++];
        const Integer old = low;
        high = old + range * (cumulative + table.frequency[symbol]) / table.total - 1;
        low = old + range * cumulative / table.total;
        while (true) {
            if (high < half) {
            } else if (low >= half) {
                low -= half;
                high -= half;
                value -= half;
            } else if (low >= quarter && high < three) {
                low -= quarter;
                high -= quarter;
                value -= quarter;
            } else
                break;
            low *= 2;
            high = 2 * high + 1;
            value = 2 * value + reader.read(1);
        }
        if (symbol == 256) {
            if (output.size() < size)
                throw DecodeError{"early_end"};
            return;
        }
        if (output.size() == size)
            throw DecodeError{"overrun"};
        output.push_back(Byte(symbol));
        table.update(symbol, rescales);
        context = symbol;
    }
}
