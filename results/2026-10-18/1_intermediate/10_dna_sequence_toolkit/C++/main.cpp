#include <algorithm>
#include <array>
#include <cctype>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;

class CommandError : public runtime_error {
public:
    using runtime_error::runtime_error;
};

const string bases = "ACGT";
const map<char, string> iupac{
    {'A', "A"}, {'C', "C"}, {'G', "G"}, {'T', "T"}, {'R', "AG"},
    {'Y', "CT"}, {'W', "AT"}, {'S', "CG"}, {'K', "GT"}, {'M', "AC"},
    {'B', "CGT"}, {'D', "AGT"}, {'H', "ACT"}, {'V', "ACG"}, {'N', "ACGT"},
};
const map<char, char> complements{
    {'A', 'T'}, {'C', 'G'}, {'G', 'C'}, {'T', 'A'}, {'R', 'Y'},
    {'Y', 'R'}, {'W', 'W'}, {'S', 'S'}, {'K', 'M'}, {'M', 'K'},
    {'B', 'V'}, {'D', 'H'}, {'H', 'D'}, {'V', 'B'}, {'N', 'N'},
};
const map<char, string> genetic_groups{
    {'A', "GCT GCC GCA GCG"}, {'C', "TGT TGC"}, {'D', "GAT GAC"},
    {'E', "GAA GAG"}, {'F', "TTT TTC"}, {'G', "GGT GGC GGA GGG"},
    {'H', "CAT CAC"}, {'I', "ATT ATC ATA"}, {'K', "AAA AAG"},
    {'L', "TTA TTG CTT CTC CTA CTG"}, {'M', "ATG"}, {'N', "AAT AAC"},
    {'P', "CCT CCC CCA CCG"}, {'Q', "CAA CAG"},
    {'R', "CGT CGC CGA CGG AGA AGG"}, {'S', "TCT TCC TCA TCG AGT AGC"},
    {'T', "ACT ACC ACA ACG"}, {'V', "GTT GTC GTA GTG"}, {'W', "TGG"},
    {'Y', "TAT TAC"}, {'*', "TAA TAG TGA"},
};
const map<char, int> amino_mass{
    {'A', 71079}, {'C', 103139}, {'D', 115089}, {'E', 129116},
    {'F', 147177}, {'G', 57052}, {'H', 137141}, {'I', 113160},
    {'K', 128174}, {'L', 113160}, {'M', 131193}, {'N', 114104},
    {'P', 97117}, {'Q', 128131}, {'R', 156188}, {'S', 87078},
    {'T', 101105}, {'V', 99133}, {'W', 186213}, {'Y', 163176},
};
const map<char, int> base_mass{
    {'A', 331222}, {'C', 307197}, {'G', 347221}, {'T', 322208},
};
const map<string, pair<string, int>> enzymes{
    {"EcoRI", {"GAATTC", 1}}, {"BamHI", {"GGATCC", 1}},
    {"HindIII", {"AAGCTT", 1}}, {"PstI", {"CTGCAG", 5}},
    {"SmaI", {"CCCGGG", 3}}, {"KpnI", {"GGTACC", 5}},
    {"XbaI", {"TCTAGA", 1}}, {"NotI", {"GCGGCCGC", 2}},
    {"EcoRV", {"GATATC", 3}}, {"HaeIII", {"GGCC", 2}},
    {"AluI", {"AGCT", 2}}, {"TaqI", {"TCGA", 1}},
    {"Sau3AI", {"GATC", 0}}, {"HincII", {"GTYRAC", 3}},
    {"AvaI", {"CYCGRG", 1}},
};
const map<string, pair<int, int>> arities{
    {"SEQ", {2, 2}}, {"SLICE", {4, 4}}, {"JOIN", {3, 9}},
    {"MUTATE", {3, 3}}, {"DEL", {1, 1}}, {"LIST", {0, 0}},
    {"REVCOMP", {1, 1}}, {"COMPLEMENT", {1, 1}}, {"REVERSE", {1, 1}},
    {"TRANSCRIBE", {1, 1}}, {"TRANSLATE", {2, 2}}, {"CODONS", {2, 2}},
    {"PROTEIN", {2, 2}}, {"ORFS", {2, 2}}, {"GC", {1, 1}},
    {"GCWINDOW", {3, 3}}, {"SKEW", {1, 1}}, {"KMERS", {3, 3}},
    {"FIND", {2, 2}}, {"RESTRICT", {2, 7}}, {"PALINDROMES", {3, 3}},
    {"REPEATS", {4, 4}}, {"HAMMING", {2, 2}}, {"ALIGN", {6, 6}},
    {"CONSENSUS", {2, 10}}, {"TM", {1, 1}}, {"MASS", {1, 1}},
    {"PRIMER", {1, 1}}, {"FOLD", {2, 2}}, {"ASSEMBLE", {4, 10}},
    {"PACK", {1, 1}}, {"UNPACK", {3, 3}},
};

map<string, char> genetic_code() {
    map<string, char> code;
    for (const auto& [amino, group] : genetic_groups) {
        istringstream stream(group);
        string codon;
        while (stream >> codon) code[codon] = amino;
    }
    return code;
}

string complement(const string& sequence) {
    string result = sequence;
    for (char& base : result) base = complements.at(base);
    return result;
}

string revcomp(const string& sequence) {
    string result = complement(sequence);
    reverse(result.begin(), result.end());
    return result;
}

int gc(const string& sequence) {
    return count_if(sequence.begin(), sequence.end(),
                    [](char c) { return c == 'G' || c == 'C'; });
}

string fixed(int value, int places) {
    int scale = 1;
    for (int i = 0; i < places; ++i) scale *= 10;
    ostringstream stream;
    stream << value / scale << '.' << setw(places) << setfill('0') << value % scale;
    return stream.str();
}

string pct(int part, int whole) {
    return fixed(10000 * part / whole, 2);
}

bool transition(char a, char b) {
    return a != b && ((a == 'A' && b == 'G') || (a == 'G' && b == 'A') ||
                      (a == 'C' && b == 'T') || (a == 'T' && b == 'C'));
}

template <typename T>
vector<T> frequency_order(const map<T, int>& counts) {
    vector<T> keys;
    for (const auto& [key, count] : counts) keys.push_back(key);
    sort(keys.begin(), keys.end(), [&](const T& a, const T& b) {
        return counts.at(a) != counts.at(b) ? counts.at(a) > counts.at(b) : a < b;
    });
    return keys;
}

vector<string> codons(const string& sequence, int frame) {
    string strand = frame > 0 ? sequence : revcomp(sequence);
    vector<string> result;
    for (size_t i = static_cast<size_t>(abs(frame) - 1); i + 2 < strand.size(); i += 3)
        result.push_back(strand.substr(i, 3));
    return result;
}

vector<int> occurrences(const string& sequence, const string& motif) {
    vector<int> positions;
    for (size_t i = 0; i + motif.size() <= sequence.size(); ++i) {
        bool matches = true;
        for (size_t j = 0; j < motif.size(); ++j) {
            if (iupac.at(motif[j]).find(sequence[i + j]) == string::npos) {
                matches = false;
                break;
            }
        }
        if (matches) positions.push_back(static_cast<int>(i) + 1);
    }
    return positions;
}

int repeat_count(const string& sequence, size_t position, size_t width) {
    string unit = sequence.substr(position, width);
    int result = 0;
    while (position + (result + 1) * width <= sequence.size() &&
           sequence.substr(position + result * width, width) == unit) ++result;
    return result;
}

bool primitive(const string& unit) {
    for (size_t width = 1; width < unit.size(); ++width) {
        if (unit.size() % width) continue;
        bool repeated = true;
        for (size_t i = width; i < unit.size(); ++i) {
            if (unit[i] != unit[i % width]) {
                repeated = false;
                break;
            }
        }
        if (repeated) return false;
    }
    return true;
}

int longest_palindrome(const string& sequence) {
    int best = 0;
    for (int center = 1; center < static_cast<int>(sequence.size()); ++center) {
        int left = center - 1, right = center;
        while (left >= 0 && right < static_cast<int>(sequence.size()) &&
               complements.at(sequence[left]) == sequence[right]) {
            best = max(best, right - left + 1);
            --left;
            ++right;
        }
    }
    return best;
}

int temperature(const string& sequence) {
    int n = static_cast<int>(sequence.size()), amount = gc(sequence);
    return n < 14 ? 10 * (2 * (n - amount) + 4 * amount)
                  : (649 * n + 410 * amount - 6724) / n;
}

int strand_mass(const string& sequence) {
    int total = 0;
    for (char base : sequence) total += base_mass.at(base);
    return total - (static_cast<int>(sequence.size()) - 1) * 18015;
}

vector<string> kinds(const string& command, size_t count) {
    if (command == "SEQ") return {"new", "sequence"};
    if (command == "SLICE") return {"name", "position", "position", "new"};
    if (command == "JOIN") {
        vector<string> result(count, "name");
        result[0] = "new";
        return result;
    }
    if (command == "MUTATE") return {"name", "position", "base"};
    if (command == "TRANSLATE" || command == "CODONS" || command == "PROTEIN")
        return {"name", "frame"};
    if (command == "ORFS") return {"name", "orf"};
    if (command == "GCWINDOW") return {"name", "window", "window"};
    if (command == "KMERS") return {"name", "kmer", "limit"};
    if (command == "FIND") return {"name", "motif"};
    if (command == "RESTRICT") {
        vector<string> result(count, "enzyme");
        result[0] = "name";
        return result;
    }
    if (command == "PALINDROMES") return {"name", "palindrome", "palindrome"};
    if (command == "REPEATS") return {"name", "repeat", "repeat", "repeat_count"};
    if (command == "ALIGN") return {"name", "name", "mode", "match", "mismatch", "gap"};
    if (command == "FOLD") return {"name", "loop"};
    if (command == "ASSEMBLE") {
        vector<string> result(count, "name");
        result[0] = "new";
        result[1] = "overlap";
        return result;
    }
    if (command == "UNPACK") return {"new", "length", "hex"};
    return vector<string>(count, "name");
}

int number(const string& text, int minimum, int maximum, bool nonzero = false) {
    size_t start = text[0] == '-' ? 1 : 0;
    if (start == text.size() || text.size() - start > 6) throw CommandError("invalid number " + text);
    for (size_t i = start; i < text.size(); ++i)
        if (!isdigit(static_cast<unsigned char>(text[i])))
            throw CommandError("invalid number " + text);
    int value = stoi(text);
    if (value < minimum || value > maximum || (nonzero && value == 0))
        throw CommandError("invalid number " + text);
    return value;
}

class Toolkit {
    map<string, string> sequences;
    vector<string> output;
    const map<string, char> code = genetic_code();

    template <typename... Args>
    void emit(const Args&... args) {
        ostringstream stream;
        bool first = true;
        ((stream << (first ? "" : " ") << args, first = false), ...);
        output.push_back(stream.str());
    }

    template <typename T>
    void emit_list(const string& label, const vector<T>& values) {
        ostringstream stream;
        stream << label;
        if (values.empty()) stream << " none";
        else for (const T& value : values) stream << ' ' << value;
        emit(stream.str());
    }

    vector<string> validate(const string& command, const vector<string>& args) const {
        auto arity = arities.find(command);
        if (arity == arities.end()) throw CommandError("unknown command " + command);
        if (args.size() < static_cast<size_t>(arity->second.first) ||
            args.size() > static_cast<size_t>(arity->second.second))
            throw CommandError("wrong argument count");

        vector<string> validated = args;
        vector<string> arg_kinds = kinds(command, args.size());
        set<string> seen_enzymes;
        for (size_t i = 0; i < args.size(); ++i) {
            const string& kind = arg_kinds[i];
            const string& text = args[i];
            if (kind == "position" || kind == "frame" || kind == "orf" ||
                kind == "window" || kind == "kmer" || kind == "limit" ||
                kind == "palindrome" || kind == "repeat" || kind == "repeat_count" ||
                kind == "match" || kind == "mismatch" || kind == "gap" ||
                kind == "loop" || kind == "overlap" || kind == "length") {
                int lower = 1, upper = 500;
                if (kind == "position") upper = static_cast<int>(sequences.at(args[0]).size());
                else if (kind == "frame") lower = -3, upper = 3;
                else if (kind == "orf") upper = 200;
                else if (kind == "kmer") upper = 12;
                else if (kind == "limit") upper = 100;
                else if (kind == "palindrome") lower = 2, upper = 20;
                else if (kind == "repeat") upper = 6;
                else if (kind == "repeat_count") lower = 2, upper = 50;
                else if (kind == "match") upper = 20;
                else if (kind == "mismatch") lower = -20, upper = 0;
                else if (kind == "gap") lower = -20, upper = -1;
                else if (kind == "loop") lower = 0, upper = 10;
                else if (kind == "overlap") upper = 100;
                (void) number(text, lower, upper, kind == "frame");
            } else if (kind == "name") {
                if (!sequences.count(text)) throw CommandError("unknown sequence " + text);
            } else if (kind == "new") {
                bool good = !text.empty() && text.size() <= 10 && text[0] >= 'a' && text[0] <= 'z';
                for (char c : text)
                    if (!(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9')) good = false;
                if (!good) throw CommandError("invalid name " + text);
            } else if (kind == "sequence") {
                for (size_t p = 0; p < text.size(); ++p)
                    if (bases.find(text[p]) == string::npos)
                        throw CommandError("invalid base " + string(1, text[p]) +
                                           " at " + to_string(p + 1));
            } else if (kind == "base") {
                if (text.size() != 1 || bases.find(text[0]) == string::npos)
                    throw CommandError("invalid base " + text);
            } else if (kind == "motif") {
                bool good = !text.empty() && text.size() <= 30;
                for (char c : text) if (!iupac.count(c)) good = false;
                if (!good) throw CommandError("invalid motif " + text);
            } else if (kind == "enzyme") {
                if (!enzymes.count(text)) throw CommandError("unknown enzyme " + text);
                if (!seen_enzymes.insert(text).second)
                    throw CommandError("duplicate enzyme " + text);
            } else if (kind == "mode") {
                if (text != "GLOBAL" && text != "LOCAL")
                    throw CommandError("invalid mode " + text);
            } else if (kind == "hex") {
                int length = stoi(args[1]);
                bool good = text.size() == static_cast<size_t>(2 * ((length + 3) / 4));
                for (char c : text)
                    if (!(c >= '0' && c <= '9') && !(c >= 'A' && c <= 'F')) good = false;
                if (!good) throw CommandError("invalid hex");
            }
        }
        return validated;
    }

    string store(const string& name, const string& sequence) {
        if (sequence.size() > 500) throw CommandError("too long");
        string action = sequences.count(name) ? "replaced" : "stored";
        sequences[name] = sequence;
        return action + " " + name + " " + to_string(sequence.size()) + " nt";
    }

    void translation(const string& command, const string& name, int frame) {
        vector<string> triplets = codons(sequences.at(name), frame);
        string protein;
        for (const string& codon : triplets) protein += code.at(codon);
        if (command == "TRANSLATE") {
            emit(protein.empty() ? "none" : protein);
        } else if (command == "CODONS") {
            map<string, int> counts;
            for (const string& codon : triplets) ++counts[codon];
            if (counts.empty()) emit("none");
            for (const string& codon : frequency_order(counts))
                emit(codon, code.at(codon), counts.at(codon));
        } else {
            protein.erase(protein.find('*'));
            if (protein.empty()) throw CommandError("empty protein");
            map<char, int> counts;
            int mass = 18015, charge = 0;
            for (char amino : protein) {
                ++counts[amino];
                mass += amino_mass.at(amino);
                charge += (amino == 'K' || amino == 'R') - (amino == 'D' || amino == 'E');
            }
            emit(protein);
            emit("length", protein.size(), "mass", fixed(mass, 3), "charge",
                 charge > 0 ? "+" + to_string(charge) : to_string(charge));
            string composition;
            for (char amino : frequency_order(counts)) {
                if (!composition.empty()) composition += ' ';
                composition += string(1, amino) + "=" + to_string(counts[amino]);
            }
            emit(composition);
        }
    }

    void orfs(const string& sequence, int minimum) {
        vector<tuple<int, int, int, string>> results;
        for (int frame : {1, 2, 3, -1, -2, -3}) {
            vector<string> triplets = codons(sequence, frame);
            optional<int> start;
            for (int position = 0; position < static_cast<int>(triplets.size()); ++position) {
                const string& codon = triplets[position];
                if (!start) {
                    if (codon == "ATG") start = position;
                } else if (code.at(codon) == '*') {
                    if (position - *start >= minimum) {
                        int left = abs(frame) - 1 + 3 * *start;
                        int right = abs(frame) - 1 + 3 * (position + 1);
                        if (frame < 0) {
                            int prior_left = left;
                            left = static_cast<int>(sequence.size()) - right;
                            right = static_cast<int>(sequence.size()) - prior_left;
                        }
                        string protein;
                        for (int p = *start; p < position; ++p) protein += code.at(triplets[p]);
                        results.emplace_back(left + 1, right, frame, protein);
                    }
                    start.reset();
                }
            }
        }
        sort(results.begin(), results.end());
        if (results.empty()) emit("none");
        for (const auto& [left, right, frame, protein] : results) {
            ostringstream sign;
            sign << (frame > 0 ? "+" : "") << frame;
            emit(sign.str(), left, right, protein.size(), protein);
        }
    }

    void restriction(const string& sequence, const vector<string>& chosen) {
        set<int> combined;
        for (const string& enzyme : chosen) {
            auto [motif, offset] = enzymes.at(enzyme);
            vector<int> points;
            for (int position : occurrences(sequence, motif)) {
                int cut = position + offset - 1;
                if (cut >= 1 && cut < static_cast<int>(sequence.size())) {
                    points.push_back(cut);
                    combined.insert(cut);
                }
            }
            emit_list(enzyme, points);
        }
        vector<int> endpoints{0};
        endpoints.insert(endpoints.end(), combined.begin(), combined.end());
        endpoints.push_back(static_cast<int>(sequence.size()));
        vector<string> fragments;
        vector<int> sizes;
        for (size_t i = 1; i < endpoints.size(); ++i) {
            int left = endpoints[i - 1] + 1, right = endpoints[i];
            fragments.push_back(to_string(left) + "-" + to_string(right));
            sizes.push_back(right - left + 1);
        }
        sort(sizes.rbegin(), sizes.rend());
        emit_list("fragments", fragments);
        emit_list("sizes", sizes);
    }

    void repeats(const string& sequence, int minimum, int maximum, int count) {
        if (minimum > maximum) throw CommandError("invalid range");
        vector<tuple<int, int, int, string>> results;
        for (int width = minimum; width <= maximum; ++width) {
            int position = 0;
            while (position + width <= static_cast<int>(sequence.size())) {
                string unit = sequence.substr(position, width);
                int repeated = repeat_count(sequence, position, width);
                if (primitive(unit) && repeated >= count) {
                    results.emplace_back(position, width, repeated, unit);
                    position += repeated * width;
                } else ++position;
            }
        }
        sort(results.begin(), results.end());
        if (results.empty()) emit("none");
        for (const auto& [position, width, repeated, unit] : results)
            emit(to_string(position + 1) + "-" + to_string(position + width * repeated),
                 unit + "x" + to_string(repeated));
    }

    void alignment(const string& a, const string& b, const string& mode,
                   int match, int mismatch, int gap) {
        int m = static_cast<int>(a.size()), n = static_cast<int>(b.size());
        bool local = mode == "LOCAL";
        vector<vector<int>> matrix(m + 1, vector<int>(n + 1, 0));
        if (!local) {
            for (int i = 0; i <= m; ++i) matrix[i][0] = i * gap;
            for (int j = 0; j <= n; ++j) matrix[0][j] = j * gap;
        }
        int best = 0, end_i = 0, end_j = 0;
        for (int i = 1; i <= m; ++i) {
            for (int j = 1; j <= n; ++j) {
                int diagonal = matrix[i - 1][j - 1] +
                               (a[i - 1] == b[j - 1] ? match : mismatch);
                int score = max({diagonal, matrix[i - 1][j] + gap, matrix[i][j - 1] + gap});
                matrix[i][j] = local ? max(0, score) : score;
                if (local && matrix[i][j] > best) {
                    best = matrix[i][j];
                    end_i = i;
                    end_j = j;
                }
            }
        }
        if (!local) {
            best = matrix[m][n];
            end_i = m;
            end_j = n;
        }
        if (local && best == 0) {
            emit("score", 0);
            return;
        }
        int i = end_i, j = end_j;
        string row_a, row_b;
        while ((local && matrix[i][j] != 0) || (!local && (i != 0 || j != 0))) {
            if (i && j && matrix[i][j] == matrix[i - 1][j - 1] +
                (a[i - 1] == b[j - 1] ? match : mismatch)) {
                row_a += a[--i];
                row_b += b[--j];
            } else if (i && matrix[i][j] == matrix[i - 1][j] + gap) {
                row_a += a[--i];
                row_b += '-';
            } else {
                row_a += '-';
                row_b += b[--j];
            }
        }
        reverse(row_a.begin(), row_a.end());
        reverse(row_b.begin(), row_b.end());
        string middle;
        for (size_t p = 0; p < row_a.size(); ++p) {
            if (row_a[p] == '-' || row_b[p] == '-') middle += '-';
            else middle += row_a[p] == row_b[p] ? '|' : '*';
        }
        emit("score", best, "a", to_string(i + 1) + "-" + to_string(end_i),
             "b", to_string(j + 1) + "-" + to_string(end_j),
             "identity", to_string(count(middle.begin(), middle.end(), '|')) +
                         "/" + to_string(middle.size()),
             "gaps", count(middle.begin(), middle.end(), '-'));
        emit(row_a);
        emit(middle);
        emit(row_b);
    }

    void consensus(const vector<string>& names) {
        size_t n = sequences.at(names.front()).size();
        for (const string& name : names)
            if (sequences.at(name).size() != n) throw CommandError("length mismatch");
        array<vector<int>, 4> profile;
        string sequence, ambiguous;
        map<string, char> symbol;
        for (const auto& [character, values] : iupac) symbol[values] = character;
        for (size_t position = 0; position < n; ++position) {
            array<int, 4> counts{};
            for (const string& name : names) {
                int code = static_cast<int>(bases.find(sequences.at(name)[position]));
                ++counts[code];
            }
            int largest = *max_element(counts.begin(), counts.end());
            string tied;
            for (int i = 0; i < 4; ++i) {
                profile[i].push_back(counts[i]);
                if (counts[i] == largest) tied += bases[i];
            }
            sequence += tied[0];
            ambiguous += symbol.at(tied);
        }
        for (int i = 0; i < 4; ++i) {
            ostringstream row;
            row << bases[i];
            for (int count : profile[i]) row << ' ' << count;
            emit(row.str());
        }
        emit("consensus", sequence);
        emit("iupac", ambiguous);
    }

    void primer(const string& sequence) {
        int n = static_cast<int>(sequence.size());
        int amount = gc(sequence), tm = temperature(sequence);
        int clamp = gc(sequence.substr(n > 5 ? n - 5 : 0));
        int longest_run = 0, run = 0, repeated = 0;
        char previous = '\0';
        for (char base : sequence) {
            run = base == previous ? run + 1 : 1;
            longest_run = max(longest_run, run);
            previous = base;
        }
        for (int i = 0; i + 1 < n; ++i)
            if (sequence[i] != sequence[i + 1])
                repeated = max(repeated, repeat_count(sequence, i, 2));
        int selfcomp = longest_palindrome(sequence);
        vector<tuple<string, string, bool>> checks{
            {"length", to_string(n), 18 <= n && n <= 25},
            {"gc", pct(amount, n), 40 * n <= 100 * amount && 100 * amount <= 60 * n},
            {"tm", fixed(tm, 1), 520 <= tm && tm <= 620},
            {"clamp", to_string(clamp), 1 <= clamp && clamp <= 3},
            {"run", to_string(longest_run), longest_run <= 4},
            {"repeat", to_string(repeated), repeated <= 4},
            {"selfcomp", to_string(selfcomp), selfcomp <= 6},
        };
        string summary;
        for (const auto& [label, value, passed] : checks) {
            emit(label, value, passed ? "OK" : "FAIL");
            if (!passed) summary += " " + label;
        }
        emit(summary.empty() ? "PASS" : "FAIL" + summary);
    }

    void folding(const string& sequence, int loop) {
        int n = static_cast<int>(sequence.size());
        if (n > 100) throw CommandError("too long");
        vector<vector<int>> table(n, vector<int>(n, 0));
        auto value = [&](int i, int j) {
            return i > j ? 0 : table[i][j];
        };
        auto paired = [&](int i, int j) {
            string pair = string(1, sequence[i]) + sequence[j];
            return pair == "AT" || pair == "TA" || pair == "CG" ||
                   pair == "GC" || pair == "GT" || pair == "TG";
        };
        for (int width = 2; width <= n; ++width) {
            for (int i = 0; i + width <= n; ++i) {
                int j = i + width - 1;
                int best = value(i, j - 1);
                for (int k = i; k < j - loop; ++k)
                    if (paired(k, j))
                        best = max(best, value(i, k - 1) + 1 + value(k + 1, j - 1));
                table[i][j] = best;
            }
        }
        string structure(n, '.');
        vector<pair<int, int>> pending{{0, n - 1}};
        while (!pending.empty()) {
            auto [i, j] = pending.back();
            pending.pop_back();
            if (i > j || value(i, j) == 0) continue;
            if (value(i, j) == value(i, j - 1)) {
                pending.emplace_back(i, j - 1);
                continue;
            }
            for (int k = i; k < j - loop; ++k) {
                if (paired(k, j) && value(i, k - 1) + 1 + value(k + 1, j - 1) ==
                    value(i, j)) {
                    structure[k] = '(';
                    structure[j] = ')';
                    pending.emplace_back(i, k - 1);
                    pending.emplace_back(k + 1, j - 1);
                    break;
                }
            }
        }
        emit(structure);
        emit("pairs", table[0][n - 1]);
    }

    void assembly(const string& name, int minimum, const vector<string>& sequences_in) {
        vector<string> fragments;
        for (const string& sequence : sequences_in)
            if (find(fragments.begin(), fragments.end(), sequence) == fragments.end())
                fragments.push_back(sequence);
        vector<string> reduced;
        for (const string& sequence : fragments) {
            bool contained = false;
            for (const string& other : fragments)
                if (sequence != other && other.find(sequence) != string::npos) {
                    contained = true;
                    break;
                }
            if (!contained) reduced.push_back(sequence);
        }
        fragments = move(reduced);
        while (fragments.size() >= 2) {
            int best = 0, chosen_i = -1, chosen_j = -1;
            for (size_t i = 0; i < fragments.size(); ++i) {
                for (size_t j = 0; j < fragments.size(); ++j) {
                    if (i == j) continue;
                    const string& a = fragments[i];
                    const string& b = fragments[j];
                    int limit = static_cast<int>(min(a.size(), b.size())) - 1;
                    int overlap = 0;
                    for (int width = limit; width >= 1; --width) {
                        if (a.compare(a.size() - width, width, b, 0, width) == 0) {
                            overlap = width;
                            break;
                        }
                    }
                    if (chosen_i == -1 || overlap > best) {
                        best = overlap;
                        chosen_i = static_cast<int>(i);
                        chosen_j = static_cast<int>(j);
                    }
                }
            }
            if (best < minimum) break;
            string merged = fragments[chosen_i] + fragments[chosen_j].substr(best);
            vector<string> next;
            for (int i = 0; i < static_cast<int>(fragments.size()); ++i) {
                if (i == chosen_i) next.push_back(merged);
                else if (i != chosen_j && merged.find(fragments[i]) == string::npos)
                    next.push_back(fragments[i]);
            }
            fragments = move(next);
        }
        const string& longest = *max_element(
            fragments.begin(), fragments.end(),
            [](const string& a, const string& b) { return a.size() < b.size(); });
        string registration = store(name, longest);
        emit("contigs", fragments.size());
        for (const string& fragment : fragments) emit(fragment.size(), fragment);
        emit(registration);
    }

    void command(const string& cmd, const vector<string>& a) {
        if (cmd == "SEQ") {
            emit(store(a[0], a[1]));
            return;
        }
        if (cmd == "UNPACK") {
            vector<int> codes;
            for (size_t i = 0; i < a[2].size(); i += 2) {
                int byte = stoi(a[2].substr(i, 2), nullptr, 16);
                codes.push_back(byte / 64);
                codes.push_back(byte / 16 % 4);
                codes.push_back(byte / 4 % 4);
                codes.push_back(byte % 4);
            }
            int n = stoi(a[1]);
            for (size_t i = static_cast<size_t>(n); i < codes.size(); ++i)
                if (codes[i] != 0) throw CommandError("invalid padding");
            string unpacked;
            for (int i = 0; i < n; ++i) unpacked += bases[codes[i]];
            emit(store(a[0], unpacked));
            return;
        }
        if (cmd == "JOIN") {
            string joined;
            for (size_t i = 1; i < a.size(); ++i) joined += sequences.at(a[i]);
            emit(store(a[0], joined));
            return;
        }
        if (cmd == "ASSEMBLE") {
            vector<string> fragments;
            for (size_t i = 2; i < a.size(); ++i) fragments.push_back(sequences.at(a[i]));
            assembly(a[0], stoi(a[1]), fragments);
            return;
        }
        if (cmd == "LIST") {
            if (sequences.empty()) emit("no sequences");
            for (const auto& [name, sequence] : sequences)
                emit(name, sequence.size(), "nt");
            return;
        }

        string name = a[0];
        string sequence = sequences.at(name);
        int n = static_cast<int>(sequence.size());
        if (cmd == "SLICE") {
            int first = stoi(a[1]), last = stoi(a[2]);
            string part = first <= last ? sequence.substr(first - 1, last - first + 1)
                : revcomp(sequence.substr(last - 1, first - last + 1));
            emit(store(a[3], part));
        } else if (cmd == "MUTATE") {
            int position = stoi(a[1]);
            char before = sequence[position - 1];
            char after = a[2][0];
            if (before == after) throw CommandError("no change");
            sequence[position - 1] = after;
            sequences[name] = sequence;
            emit(name, string(1, before) + to_string(position) + after,
                 transition(before, after) ? "transition" : "transversion");
        } else if (cmd == "DEL") {
            sequences.erase(name);
            emit("deleted", name);
        } else if (cmd == "REVCOMP") emit(revcomp(sequence));
        else if (cmd == "COMPLEMENT") emit(complement(sequence));
        else if (cmd == "REVERSE") {
            reverse(sequence.begin(), sequence.end());
            emit(sequence);
        } else if (cmd == "TRANSCRIBE") {
            replace(sequence.begin(), sequence.end(), 'T', 'U');
            emit(sequence);
        } else if (cmd == "TRANSLATE" || cmd == "CODONS" || cmd == "PROTEIN") {
            translation(cmd, name, stoi(a[1]));
        } else if (cmd == "ORFS") orfs(sequence, stoi(a[1]));
        else if (cmd == "GC") {
            string text;
            for (char base : bases) {
                if (!text.empty()) text += ' ';
                text += string(1, base) + "=" + to_string(count(sequence.begin(), sequence.end(), base));
            }
            emit(text + " GC=" + pct(gc(sequence), n) + "%");
        } else if (cmd == "GCWINDOW") {
            int width = stoi(a[1]), step = stoi(a[2]);
            if (width > n) throw CommandError("window too large");
            for (int i = 0; i + width <= n; i += step)
                emit(to_string(i + 1) + "-" + to_string(i + width),
                     pct(gc(sequence.substr(i, width)), width) + "%");
        } else if (cmd == "SKEW") {
            vector<int> values{0};
            for (char base : sequence)
                values.push_back(values.back() + (base == 'G') - (base == 'C'));
            for (string label : {"min", "max"}) {
                int extreme = label == "min" ?
                    *min_element(values.begin(), values.end()) :
                    *max_element(values.begin(), values.end());
                ostringstream result;
                result << label << ' ' << extreme << " at";
                for (size_t i = 0; i < values.size(); ++i)
                    if (values[i] == extreme) result << ' ' << i;
                emit(result.str());
            }
        } else if (cmd == "KMERS") {
            int width = stoi(a[1]), limit = stoi(a[2]);
            if (width > n) throw CommandError("k too large");
            map<string, int> counts;
            for (int i = 0; i + width <= n; ++i) ++counts[sequence.substr(i, width)];
            emit(n - width + 1, "windows", counts.size(), "distinct");
            vector<string> words = frequency_order(counts);
            for (int i = 0; i < min(limit, static_cast<int>(words.size())); ++i)
                emit(words[i], counts.at(words[i]));
        } else if (cmd == "FIND") {
            emit_list("forward", occurrences(sequence, a[1]));
            emit_list("reverse", occurrences(sequence, revcomp(a[1])));
        } else if (cmd == "RESTRICT") {
            restriction(sequence, vector<string>(a.begin() + 1, a.end()));
        } else if (cmd == "PALINDROMES") {
            int minimum = stoi(a[1]), maximum = stoi(a[2]);
            if (minimum > maximum) throw CommandError("invalid range");
            bool found = false;
            for (int i = 0; i < n; ++i) {
                for (int width = minimum; width <= maximum && i + width <= n; ++width) {
                    string part = sequence.substr(i, width);
                    if (part == revcomp(part)) {
                        emit(i + 1, width, part);
                        found = true;
                    }
                }
            }
            if (!found) emit("none");
        } else if (cmd == "REPEATS") {
            repeats(sequence, stoi(a[1]), stoi(a[2]), stoi(a[3]));
        } else if (cmd == "HAMMING") {
            string other = sequences.at(a[1]);
            if (other.size() != sequence.size()) throw CommandError("length mismatch");
            int distance = 0, transitions = 0;
            for (int i = 0; i < n; ++i) {
                if (sequence[i] != other[i]) {
                    ++distance;
                    transitions += transition(sequence[i], other[i]);
                }
            }
            emit("distance", distance, "transitions", transitions,
                 "transversions", distance - transitions);
        } else if (cmd == "ALIGN") {
            alignment(sequence, sequences.at(a[1]), a[2], stoi(a[3]),
                      stoi(a[4]), stoi(a[5]));
        } else if (cmd == "CONSENSUS") consensus(a);
        else if (cmd == "TM")
            emit("Tm", fixed(temperature(sequence), 1), n < 14 ? "wallace" : "gc");
        else if (cmd == "MASS") {
            int single = strand_mass(sequence);
            emit("ss", fixed(single, 3),
                 "ds", fixed(single + strand_mass(revcomp(sequence)), 3));
        } else if (cmd == "PRIMER") primer(sequence);
        else if (cmd == "FOLD") folding(sequence, stoi(a[1]));
        else if (cmd == "PACK") {
            vector<int> codes;
            for (char base : sequence)
                codes.push_back(static_cast<int>(bases.find(base)));
            while (codes.size() % 4) codes.push_back(0);
            ostringstream encoded;
            encoded << uppercase << hex << setfill('0');
            for (size_t i = 0; i < codes.size(); i += 4) {
                int byte = 64 * codes[i] + 16 * codes[i + 1] +
                           4 * codes[i + 2] + codes[i + 3];
                encoded << setw(2) << byte;
            }
            emit(n, encoded.str());
        }
    }

public:
    void execute(const string& line) {
        istringstream stream(line);
        string command_name;
        stream >> command_name;
        vector<string> args;
        string word;
        while (stream >> word) args.push_back(word);
        try {
            vector<string> validated = validate(command_name, args);
            command(command_name, validated);
        } catch (const CommandError& error) {
            emit("ERROR", error.what());
        }
    }

    void print() const {
        for (const string& line : output) cout << line << '\n';
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    int count;
    cin >> count;
    cin.ignore();
    Toolkit toolkit;
    string line;
    for (int i = 0; i < count; ++i) {
        getline(cin, line);
        toolkit.execute(line);
    }
    toolkit.print();
}
