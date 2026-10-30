#include "codec.hpp"
Image read_ppm(const std::string &path) {
    std::ifstream input(path);
    std::string magic;
    int maximum;
    Image out;
    input >> magic >> out.width >> out.height >> maximum;
    out.pixels.resize(out.width * out.height);
    for (Pixel &pixel : out.pixels)
        for (I &value : pixel)
            input >> value;
    return out;
}
Params read_params() {
    std::ifstream input("input/params.txt");
    std::string text;
    Params out;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "qualities" || key == "truncate") {
            int value;
            std::vector<int> &values = key == "qualities" ? out.qualities : out.truncate;
            while (row >> value)
                values.push_back(value);
        } else if (key == "sampling")
            row >> out.sampling;
        else if (key == "restart_interval")
            row >> out.restart;
        else if (key == "huffman") {
            std::string mode;
            row >> mode;
            out.optimized = mode == "optimized";
        } else if (key == "target_bytes")
            row >> out.target;
        else if (key == "generations")
            row >> out.generations;
    }
    return out;
}
SourceTables read_tables() {
    std::ifstream input("input/tables.txt");
    SourceTables out;
    std::string key;
    input >> key;
    for (auto &row : out.transform)
        for (I &value : row)
            input >> value;
    for (int t = 0; t < 2; ++t) {
        int id;
        input >> key >> id;
        for (auto &row : out.basic[t])
            for (I &value : row)
                input >> value;
    }
    for (int t = 0; t < 4; ++t) {
        int kind, id;
        input >> key >> kind >> id;
        std::array<int, 16> counts{};
        int total = 0;
        for (int &count : counts) {
            input >> count;
            total += count;
        }
        Bytes symbols(total);
        for (int &symbol : symbols)
            input >> symbol;
        out.huffman[{kind, id}] = Huffman(counts, symbols);
    }
    return out;
}
Bytes read_hex(const std::string &path) {
    std::ifstream input(path);
    std::string text;
    Bytes out;
    while (input >> text)
        for (int i = 0; i < int(text.size()); i += 2)
            out.push_back(std::stoi(text.substr(i, 2), nullptr, 16));
    return out;
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
void write_ppm(const std::string &name, const Image &image) {
    Lines out;
    line(out, "P3");
    line(out, image.width, " ", image.height);
    line(out, "255");
    for (int y = 0; y < image.height; ++y) {
        std::string row;
        for (int x = 0; x < image.width; ++x)
            for (I value : image.pixels[y * image.width + x]) {
                if (!row.empty())
                    row += " ";
                row += std::to_string(value);
            }
        out.push_back(row);
    }
    save(name, out);
}
void write_hex(const std::string &name, const Bytes &bytes) {
    const char *digits = "0123456789abcdef";
    Lines out;
    for (int offset = 0; offset < int(bytes.size()); offset += 32) {
        std::string row;
        for (int i = offset; i < std::min(offset + 32, int(bytes.size())); ++i) {
            row += digits[bytes[i] / 16];
            row += digits[bytes[i] % 16];
        }
        out.push_back(row);
    }
    save(name, out);
}
