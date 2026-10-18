#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_SEQUENCES 400
#define MAX_LENGTH 500
#define MAX_FRAGMENT 4000
#define MAX_LINE 700

typedef struct {
    char name[11];
    char sequence[MAX_LENGTH + 1];
} Sequence;

typedef struct {
    const char *name;
    const char *motif;
    int offset;
} Enzyme;

typedef struct {
    const char *command;
    int minimum;
    int maximum;
} Arity;

typedef struct {
    char amino;
    const char *triplets;
} CodonGroup;

static const Arity arities[] = {
    {"SEQ", 2, 2}, {"SLICE", 4, 4}, {"JOIN", 3, 9},
    {"MUTATE", 3, 3}, {"DEL", 1, 1}, {"LIST", 0, 0},
    {"REVCOMP", 1, 1}, {"COMPLEMENT", 1, 1}, {"REVERSE", 1, 1},
    {"TRANSCRIBE", 1, 1}, {"TRANSLATE", 2, 2}, {"CODONS", 2, 2},
    {"PROTEIN", 2, 2}, {"ORFS", 2, 2}, {"GC", 1, 1},
    {"GCWINDOW", 3, 3}, {"SKEW", 1, 1}, {"KMERS", 3, 3},
    {"FIND", 2, 2}, {"RESTRICT", 2, 7}, {"PALINDROMES", 3, 3},
    {"REPEATS", 4, 4}, {"HAMMING", 2, 2}, {"ALIGN", 6, 6},
    {"CONSENSUS", 2, 10}, {"TM", 1, 1}, {"MASS", 1, 1},
    {"PRIMER", 1, 1}, {"FOLD", 2, 2}, {"ASSEMBLE", 4, 10},
    {"PACK", 1, 1}, {"UNPACK", 3, 3}
};

static const Enzyme enzymes[] = {
    {"EcoRI", "GAATTC", 1}, {"BamHI", "GGATCC", 1},
    {"HindIII", "AAGCTT", 1}, {"PstI", "CTGCAG", 5},
    {"SmaI", "CCCGGG", 3}, {"KpnI", "GGTACC", 5},
    {"XbaI", "TCTAGA", 1}, {"NotI", "GCGGCCGC", 2},
    {"EcoRV", "GATATC", 3}, {"HaeIII", "GGCC", 2},
    {"AluI", "AGCT", 2}, {"TaqI", "TCGA", 1},
    {"Sau3AI", "GATC", 0}, {"HincII", "GTYRAC", 3},
    {"AvaI", "CYCGRG", 1}
};

static const CodonGroup codon_groups[] = {
    {'A', "GCT GCC GCA GCG"}, {'C', "TGT TGC"}, {'D', "GAT GAC"},
    {'E', "GAA GAG"}, {'F', "TTT TTC"}, {'G', "GGT GGC GGA GGG"},
    {'H', "CAT CAC"}, {'I', "ATT ATC ATA"}, {'K', "AAA AAG"},
    {'L', "TTA TTG CTT CTC CTA CTG"}, {'M', "ATG"}, {'N', "AAT AAC"},
    {'P', "CCT CCC CCA CCG"}, {'Q', "CAA CAG"},
    {'R', "CGT CGC CGA CGG AGA AGG"}, {'S', "TCT TCC TCA TCG AGT AGC"},
    {'T', "ACT ACC ACA ACG"}, {'V', "GTT GTC GTA GTG"}, {'W', "TGG"},
    {'Y', "TAT TAC"}, {'*', "TAA TAG TGA"}
};

static Sequence registry[MAX_SEQUENCES];
static int sequence_count = 0;
static char error_message[128];

static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(error_message, sizeof(error_message), format, args);
    va_end(args);
}

static int exists(const char *name) {
    int i;
    for (i = 0; i < sequence_count; ++i)
        if (strcmp(registry[i].name, name) == 0) return i;
    return -1;
}

static const char *sequence_of(const char *name) {
    return registry[exists(name)].sequence;
}

static int store(const char *name, const char *sequence) {
    int index;
    size_t length = strlen(sequence);
    if (length > MAX_LENGTH) {
        fail("too long");
        return 0;
    }
    index = exists(name);
    if (index < 0) {
        index = sequence_count++;
        strcpy(registry[index].name, name);
        strcpy(registry[index].sequence, sequence);
        printf("stored %s %zu nt\n", name, length);
    } else {
        strcpy(registry[index].sequence, sequence);
        printf("replaced %s %zu nt\n", name, length);
    }
    return 1;
}

static char complement(char base) {
    const char *original = "ACGTRYWSKMBVDHN";
    const char *other = "TGCAYRWSMKVBHDN";
    const char *position = strchr(original, base);
    return other[position - original];
}

static void revcomp(const char *sequence, char *result) {
    size_t n = strlen(sequence), i;
    for (i = 0; i < n; ++i) result[i] = complement(sequence[n - i - 1]);
    result[n] = '\0';
}

static int gc(const char *sequence) {
    int count = 0;
    while (*sequence) {
        if (*sequence == 'G' || *sequence == 'C') ++count;
        ++sequence;
    }
    return count;
}

static void fixed(int value, int places, char *result) {
    int scale = 1, i;
    for (i = 0; i < places; ++i) scale *= 10;
    sprintf(result, "%d.%0*d", value / scale, places, value % scale);
}

static void percentage(int part, int whole, char *result) {
    fixed(10000 * part / whole, 2, result);
}

static int transition(char a, char b) {
    return a != b && (
        (a == 'A' && b == 'G') || (a == 'G' && b == 'A') ||
        (a == 'C' && b == 'T') || (a == 'T' && b == 'C'));
}

static const char *iupac(char symbol) {
    switch (symbol) {
        case 'A': return "A";
        case 'C': return "C";
        case 'G': return "G";
        case 'T': return "T";
        case 'R': return "AG";
        case 'Y': return "CT";
        case 'W': return "AT";
        case 'S': return "CG";
        case 'K': return "GT";
        case 'M': return "AC";
        case 'B': return "CGT";
        case 'D': return "AGT";
        case 'H': return "ACT";
        case 'V': return "ACG";
        case 'N': return "ACGT";
        default: return NULL;
    }
}

static char amino(const char *codon) {
    size_t i;
    for (i = 0; i < sizeof(codon_groups) / sizeof(*codon_groups); ++i) {
        const char *list = codon_groups[i].triplets;
        while (*list) {
            if (strncmp(list, codon, 3) == 0) return codon_groups[i].amino;
            list += 3;
            if (*list == ' ') ++list;
        }
    }
    return '\0';
}

static int base_mass(char base) {
    switch (base) {
        case 'A': return 331222;
        case 'C': return 307197;
        case 'G': return 347221;
        default: return 322208;
    }
}

static int amino_mass(char amino) {
    const char *labels = "ACDEFGHIKLMNPQRSTVWY";
    const int masses[] = {
        71079, 103139, 115089, 129116, 147177, 57052, 137141,
        113160, 128174, 113160, 131193, 114104, 97117, 128131,
        156188, 87078, 101105, 99133, 186213, 163176
    };
    return masses[strchr(labels, amino) - labels];
}

static const Enzyme *find_enzyme(const char *name) {
    size_t i;
    for (i = 0; i < sizeof(enzymes) / sizeof(*enzymes); ++i)
        if (strcmp(enzymes[i].name, name) == 0) return &enzymes[i];
    return NULL;
}

static int is_numeric_kind(const char *kind) {
    const char *names[] = {
        "position", "frame", "orf", "window", "kmer", "limit",
        "palindrome", "repeat", "repeat_count", "match", "mismatch",
        "gap", "loop", "overlap", "length"
    };
    size_t i;
    for (i = 0; i < sizeof(names) / sizeof(*names); ++i)
        if (strcmp(kind, names[i]) == 0) return 1;
    return 0;
}

static const char *argument_kind(const char *command, int i) {
    if (strcmp(command, "SEQ") == 0) return i == 0 ? "new" : "sequence";
    if (strcmp(command, "SLICE") == 0)
        return i == 0 ? "name" : i == 3 ? "new" : "position";
    if (strcmp(command, "JOIN") == 0)
        return i == 0 ? "new" : "name";
    if (strcmp(command, "MUTATE") == 0)
        return i == 0 ? "name" : i == 1 ? "position" : "base";
    if (strcmp(command, "ASSEMBLE") == 0)
        return i == 0 ? "new" : i == 1 ? "overlap" : "name";
    if (strcmp(command, "UNPACK") == 0)
        return i == 0 ? "new" : i == 1 ? "length" : "hex";
    if (strcmp(command, "RESTRICT") == 0)
        return i == 0 ? "name" : "enzyme";
    if (strcmp(command, "ALIGN") == 0)
        return i < 2 ? "name" : i == 2 ? "mode" :
               i == 3 ? "match" : i == 4 ? "mismatch" : "gap";
    if (i == 0) return "name";
    if (strcmp(command, "TRANSLATE") == 0 ||
        strcmp(command, "CODONS") == 0 || strcmp(command, "PROTEIN") == 0)
        return "frame";
    if (strcmp(command, "ORFS") == 0) return "orf";
    if (strcmp(command, "GCWINDOW") == 0) return "window";
    if (strcmp(command, "KMERS") == 0) return i == 1 ? "kmer" : "limit";
    if (strcmp(command, "FIND") == 0) return "motif";
    if (strcmp(command, "PALINDROMES") == 0) return "palindrome";
    if (strcmp(command, "REPEATS") == 0)
        return i == 3 ? "repeat_count" : "repeat";
    if (strcmp(command, "FOLD") == 0) return "loop";
    return "name";
}

static int valid_number(const char *text, int minimum, int maximum, int nonzero) {
    const char *digits = *text == '-' ? text + 1 : text;
    int value;
    const char *p;
    if (strlen(digits) == 0 || strlen(digits) > 6) {
        fail("invalid number %s", text);
        return 0;
    }
    for (p = digits; *p; ++p) {
        if (!isdigit((unsigned char)*p)) {
            fail("invalid number %s", text);
            return 0;
        }
    }
    value = atoi(text);
    if (value < minimum || value > maximum || (nonzero && value == 0)) {
        fail("invalid number %s", text);
        return 0;
    }
    return 1;
}

static int validate(const char *command, int count, char **args) {
    size_t k;
    int i, j, minimum, maximum, nonzero, value;
    const Arity *arity = NULL;
    for (k = 0; k < sizeof(arities) / sizeof(*arities); ++k)
        if (strcmp(arities[k].command, command) == 0) {
            arity = &arities[k];
            break;
        }
    if (!arity) {
        fail("unknown command %s", command);
        return 0;
    }
    if (count < arity->minimum || count > arity->maximum) {
        fail("wrong argument count");
        return 0;
    }
    for (i = 0; i < count; ++i) {
        const char *kind = argument_kind(command, i);
        const char *text = args[i];
        size_t len = strlen(text);
        if (is_numeric_kind(kind)) {
            minimum = 1;
            maximum = 500;
            nonzero = 0;
            if (strcmp(kind, "position") == 0) maximum = (int)strlen(sequence_of(args[0]));
            else if (strcmp(kind, "frame") == 0) minimum = -3, maximum = 3, nonzero = 1;
            else if (strcmp(kind, "orf") == 0) maximum = 200;
            else if (strcmp(kind, "kmer") == 0) maximum = 12;
            else if (strcmp(kind, "limit") == 0 ||
                     strcmp(kind, "overlap") == 0) maximum = 100;
            else if (strcmp(kind, "palindrome") == 0) minimum = 2, maximum = 20;
            else if (strcmp(kind, "repeat") == 0) maximum = 6;
            else if (strcmp(kind, "repeat_count") == 0) minimum = 2, maximum = 50;
            else if (strcmp(kind, "match") == 0) maximum = 20;
            else if (strcmp(kind, "mismatch") == 0) minimum = -20, maximum = 0;
            else if (strcmp(kind, "gap") == 0) minimum = -20, maximum = -1;
            else if (strcmp(kind, "loop") == 0) minimum = 0, maximum = 10;
            if (!valid_number(text, minimum, maximum, nonzero)) return 0;
        } else if (strcmp(kind, "name") == 0) {
            if (exists(text) < 0) {
                fail("unknown sequence %s", text);
                return 0;
            }
        } else if (strcmp(kind, "new") == 0) {
            if (!len || len > 10 || text[0] < 'a' || text[0] > 'z') {
                fail("invalid name %s", text);
                return 0;
            }
            for (j = 0; j < (int)len; ++j) {
                if (!((text[j] >= 'a' && text[j] <= 'z') ||
                      (text[j] >= '0' && text[j] <= '9'))) {
                    fail("invalid name %s", text);
                    return 0;
                }
            }
        } else if (strcmp(kind, "sequence") == 0) {
            for (j = 0; j < (int)len; ++j) {
                if (!strchr("ACGT", text[j])) {
                    fail("invalid base %c at %d", text[j], j + 1);
                    return 0;
                }
            }
        } else if (strcmp(kind, "base") == 0) {
            if (len != 1 || !strchr("ACGT", text[0])) {
                fail("invalid base %s", text);
                return 0;
            }
        } else if (strcmp(kind, "motif") == 0) {
            if (!len || len > 30) {
                fail("invalid motif %s", text);
                return 0;
            }
            for (j = 0; j < (int)len; ++j)
                if (!iupac(text[j])) {
                    fail("invalid motif %s", text);
                    return 0;
                }
        } else if (strcmp(kind, "enzyme") == 0) {
            if (!find_enzyme(text)) {
                fail("unknown enzyme %s", text);
                return 0;
            }
            for (j = 1; j < i; ++j)
                if (strcmp(args[j], text) == 0) {
                    fail("duplicate enzyme %s", text);
                    return 0;
                }
        } else if (strcmp(kind, "mode") == 0) {
            if (strcmp(text, "GLOBAL") != 0 && strcmp(text, "LOCAL") != 0) {
                fail("invalid mode %s", text);
                return 0;
            }
        } else if (strcmp(kind, "hex") == 0) {
            value = atoi(args[1]);
            if (len != (size_t)(2 * ((value + 3) / 4))) {
                fail("invalid hex");
                return 0;
            }
            for (j = 0; j < (int)len; ++j) {
                if (!isdigit((unsigned char)text[j]) ||
                    (text[j] < '0' || text[j] > '9')) {
                    if (text[j] < 'A' || text[j] > 'F') {
                        fail("invalid hex");
                        return 0;
                    }
                }
            }
        }
    }
    return 1;
}

static int get_codons(const char *sequence, int frame, char triplets[167][4]) {
    char strand[MAX_LENGTH + 1];
    int offset, n, i, count = 0;
    if (frame < 0) {
        revcomp(sequence, strand);
        frame = -frame;
    } else strcpy(strand, sequence);
    offset = frame - 1;
    n = (int)strlen(strand);
    for (i = offset; i + 2 < n; i += 3) {
        memcpy(triplets[count], strand + i, 3);
        triplets[count][3] = '\0';
        ++count;
    }
    return count;
}

static int occurrences(const char *sequence, const char *motif, int *locations) {
    int n = (int)strlen(sequence), m = (int)strlen(motif);
    int i, j, count = 0, matched;
    for (i = 0; i + m <= n; ++i) {
        matched = 1;
        for (j = 0; j < m; ++j)
            if (!strchr(iupac(motif[j]), sequence[i + j])) {
                matched = 0;
                break;
            }
        if (matched) locations[count++] = i + 1;
    }
    return count;
}

static int repeat_count(const char *sequence, int position, int width) {
    int n = (int)strlen(sequence), count = 0;
    while (position + (count + 1) * width <= n &&
           strncmp(sequence + position,
                   sequence + position + count * width, (size_t)width) == 0)
        ++count;
    return count;
}

static int primitive(const char *unit, int n) {
    int width, i, repeated;
    for (width = 1; width < n; ++width) {
        if (n % width) continue;
        repeated = 1;
        for (i = width; i < n; ++i)
            if (unit[i] != unit[i % width]) {
                repeated = 0;
                break;
            }
        if (repeated) return 0;
    }
    return 1;
}

static int palindrome_length(const char *sequence) {
    int n = (int)strlen(sequence), best = 0, center, left, right;
    for (center = 1; center < n; ++center) {
        left = center - 1;
        right = center;
        while (left >= 0 && right < n &&
               complement(sequence[left]) == sequence[right]) {
            if (right - left + 1 > best) best = right - left + 1;
            --left;
            ++right;
        }
    }
    return best;
}

static int temperature(const char *sequence) {
    int n = (int)strlen(sequence), amount = gc(sequence);
    return n < 14 ? 10 * (2 * (n - amount) + 4 * amount) :
        (649 * n + 410 * amount - 6724) / n;
}

static int strand_mass(const char *sequence) {
    int total = 0;
    const char *p;
    for (p = sequence; *p; ++p) total += base_mass(*p);
    return total - ((int)strlen(sequence) - 1) * 18015;
}

static void print_list(const char *label, const int *values, int count) {
    int i;
    printf("%s", label);
    if (count == 0) printf(" none");
    for (i = 0; i < count; ++i) printf(" %d", values[i]);
    putchar('\n');
}

static int compare_int(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a > b) - (a < b);
}

static int compare_desc(const void *left, const void *right) {
    return -compare_int(left, right);
}

typedef struct {
    int left;
    int right;
    int frame;
    char protein[168];
} Orf;

static int compare_orfs(const void *left, const void *right) {
    const Orf *a = left, *b = right;
    if (a->left != b->left) return (a->left > b->left) - (a->left < b->left);
    if (a->right != b->right) return (a->right > b->right) - (a->right < b->right);
    return (a->frame > b->frame) - (a->frame < b->frame);
}

static void orfs(const char *sequence, int minimum) {
    Orf result[600];
    int found = 0, frames[] = {1, 2, 3, -1, -2, -3};
    int i, j, position, first, n = (int)strlen(sequence);
    char codon[167][4];
    for (i = 0; i < 6; ++i) {
        int frame = frames[i], offset = abs(frame) - 1;
        int count = get_codons(sequence, frame, codon);
        first = -1;
        for (j = 0; j < count; ++j) {
            if (first < 0) {
                if (strcmp(codon[j], "ATG") == 0) first = j;
            } else if (amino(codon[j]) == '*') {
                if (j - first >= minimum) {
                    Orf *row = &result[found++];
                    int left = offset + 3 * first;
                    int right = offset + 3 * (j + 1);
                    if (frame < 0) {
                        position = left;
                        left = n - right;
                        right = n - position;
                    }
                    row->left = left + 1;
                    row->right = right;
                    row->frame = frame;
                    for (position = first; position < j; ++position)
                        row->protein[position - first] = amino(codon[position]);
                    row->protein[j - first] = '\0';
                }
                first = -1;
            }
        }
    }
    qsort(result, (size_t)found, sizeof(*result), compare_orfs);
    if (found == 0) puts("none");
    for (i = 0; i < found; ++i)
        printf("%+d %d %d %zu %s\n", result[i].frame, result[i].left,
               result[i].right, strlen(result[i].protein), result[i].protein);
}

static void translation(const char *sequence, const char *command, int frame) {
    char triplets[167][4], protein[168];
    int counts[167] = {0};
    int count = get_codons(sequence, frame, triplets), i, j;
    if (strcmp(command, "TRANSLATE") == 0) {
        if (!count) {
            puts("none");
            return;
        }
        for (i = 0; i < count; ++i) putchar(amino(triplets[i]));
        putchar('\n');
    } else if (strcmp(command, "CODONS") == 0) {
        int order[167], distinct = 0;
        for (i = 0; i < count; ++i) {
            for (j = 0; j < distinct; ++j)
                if (strcmp(triplets[order[j]], triplets[i]) == 0) break;
            if (j == distinct) order[distinct++] = i;
            ++counts[order[j]];
        }
        for (i = 0; i < distinct; ++i)
            for (j = i + 1; j < distinct; ++j)
                if (counts[order[j]] > counts[order[i]] ||
                    (counts[order[j]] == counts[order[i]] &&
                     strcmp(triplets[order[j]], triplets[order[i]]) < 0)) {
                    int temporary = order[i];
                    order[i] = order[j];
                    order[j] = temporary;
                }
        if (!distinct) puts("none");
        for (i = 0; i < distinct; ++i)
            printf("%s %c %d\n", triplets[order[i]], amino(triplets[order[i]]),
                   counts[order[i]]);
    } else {
        int composition[256] = {0}, mass = 18015, charge = 0, length = 0;
        char text[32];
        for (i = 0; i < count; ++i) {
            char aa = amino(triplets[i]);
            if (aa == '*') break;
            protein[length++] = aa;
            ++composition[(unsigned char)aa];
            mass += amino_mass(aa);
            charge += aa == 'K' || aa == 'R';
            charge -= aa == 'D' || aa == 'E';
        }
        if (!length) {
            fail("empty protein");
            return;
        }
        protein[length] = '\0';
        puts(protein);
        fixed(mass, 3, text);
        printf("length %d mass %s charge ", length, text);
        if (charge > 0) putchar('+');
        printf("%d\n", charge);
        {
            const char *labels = "ACDEFGHIKLMNPQRSTVWY";
            int first = 1;
            for (j = 0; j < 20; ++j) {
                int best = -1;
                for (i = 0; i < 20; ++i) {
                    char aa = labels[i];
                    if (composition[(unsigned char)aa] <= 0) continue;
                    if (best < 0 ||
                        composition[(unsigned char)aa] >
                            composition[(unsigned char)labels[best]] ||
                        (composition[(unsigned char)aa] ==
                            composition[(unsigned char)labels[best]] && i < best))
                        best = i;
                }
                if (best < 0) break;
                if (!first) putchar(' ');
                first = 0;
                printf("%c=%d", labels[best], composition[(unsigned char)labels[best]]);
                composition[(unsigned char)labels[best]] = 0;
            }
            putchar('\n');
        }
    }
}

static void restriction(const char *sequence, int count, char **selected) {
    int cut[MAX_LENGTH + 1] = {0}, positions[500];
    int i, j, k, found, n = (int)strlen(sequence), previous, sizes[501], fragments = 0;
    for (i = 0; i < count; ++i) {
        const Enzyme *enzyme = find_enzyme(selected[i]);
        int number = occurrences(sequence, enzyme->motif, positions);
        int printed = 0;
        printf("%s", selected[i]);
        for (j = 0; j < number; ++j) {
            int location = positions[j] + enzyme->offset - 1;
            if (location >= 1 && location < n) {
                printf(" %d", location);
                cut[location] = 1;
                printed = 1;
            }
        }
        if (!printed) printf(" none");
        putchar('\n');
    }
    printf("fragments");
    previous = 0;
    for (k = 1; k <= n; ++k) {
        if (cut[k] || k == n) {
            printf(" %d-%d", previous + 1, k);
            sizes[fragments++] = k - previous;
            previous = k;
        }
    }
    putchar('\n');
    qsort(sizes, (size_t)fragments, sizeof(*sizes), compare_desc);
    print_list("sizes", sizes, fragments);
}

typedef struct {
    int position;
    int width;
    int count;
    char unit[7];
} Repeat;

static int compare_repeats(const void *left, const void *right) {
    const Repeat *a = left, *b = right;
    if (a->position != b->position)
        return (a->position > b->position) - (a->position < b->position);
    return (a->width > b->width) - (a->width < b->width);
}

static void repeats(const char *sequence, int minimum, int maximum, int needed) {
    Repeat results[3000];
    int n = (int)strlen(sequence), found = 0;
    int width, position, repeated, i;
    if (minimum > maximum) {
        fail("invalid range");
        return;
    }
    for (width = minimum; width <= maximum; ++width) {
        position = 0;
        while (position + width <= n) {
            char unit[7];
            memcpy(unit, sequence + position, (size_t)width);
            unit[width] = '\0';
            repeated = repeat_count(sequence, position, width);
            if (primitive(unit, width) && repeated >= needed) {
                Repeat *row = &results[found++];
                row->position = position;
                row->width = width;
                row->count = repeated;
                strcpy(row->unit, unit);
                position += width * repeated;
            } else ++position;
        }
    }
    qsort(results, (size_t)found, sizeof(*results), compare_repeats);
    if (found == 0) puts("none");
    for (i = 0; i < found; ++i)
        printf("%d-%d %sx%d\n", results[i].position + 1,
               results[i].position + results[i].width * results[i].count,
               results[i].unit, results[i].count);
}

static int alignment_table[501][501];

static void alignment(const char *a, const char *b, const char *mode,
                      int match, int mismatch, int gap) {
    int m = (int)strlen(a), n = (int)strlen(b);
    int local = strcmp(mode, "LOCAL") == 0;
    int best = 0, end_i = 0, end_j = 0, i, j, score, diagonal, value;
    char left[1001], right[1001], middle[1001];
    int length = 0, identical = 0, gaps = 0, position;
    memset(alignment_table, 0, sizeof(alignment_table));
    if (!local) {
        for (i = 0; i <= m; ++i) alignment_table[i][0] = i * gap;
        for (j = 0; j <= n; ++j) alignment_table[0][j] = j * gap;
    }
    for (i = 1; i <= m; ++i) {
        for (j = 1; j <= n; ++j) {
            score = a[i - 1] == b[j - 1] ? match : mismatch;
            diagonal = alignment_table[i - 1][j - 1] + score;
            value = diagonal;
            if (alignment_table[i - 1][j] + gap > value)
                value = alignment_table[i - 1][j] + gap;
            if (alignment_table[i][j - 1] + gap > value)
                value = alignment_table[i][j - 1] + gap;
            if (local && value < 0) value = 0;
            alignment_table[i][j] = value;
            if (local && value > best) {
                best = value;
                end_i = i;
                end_j = j;
            }
        }
    }
    if (!local) {
        best = alignment_table[m][n];
        end_i = m;
        end_j = n;
    }
    if (local && best == 0) {
        puts("score 0");
        return;
    }
    i = end_i;
    j = end_j;
    while ((local && alignment_table[i][j] != 0) ||
           (!local && (i != 0 || j != 0))) {
        score = i > 0 && j > 0 && a[i - 1] == b[j - 1] ? match : mismatch;
        if (i > 0 && j > 0 &&
            alignment_table[i][j] == alignment_table[i - 1][j - 1] + score) {
            left[length] = a[--i];
            right[length] = b[--j];
        } else if (i > 0 &&
                   alignment_table[i][j] == alignment_table[i - 1][j] + gap) {
            left[length] = a[--i];
            right[length] = '-';
        } else {
            left[length] = '-';
            right[length] = b[--j];
        }
        ++length;
    }
    for (position = 0; position < length; ++position) {
        char x = left[position], y = right[position];
        if (x == '-' || y == '-') {
            middle[position] = '-';
            ++gaps;
        } else if (x == y) {
            middle[position] = '|';
            ++identical;
        } else middle[position] = '*';
    }
    printf("score %d a %d-%d b %d-%d identity %d/%d gaps %d\n",
           best, i + 1, end_i, j + 1, end_j, identical, length, gaps);
    for (position = length - 1; position >= 0; --position) putchar(left[position]);
    putchar('\n');
    for (position = length - 1; position >= 0; --position) putchar(middle[position]);
    putchar('\n');
    for (position = length - 1; position >= 0; --position) putchar(right[position]);
    putchar('\n');
}

static void consensus(int count, char **names) {
    int n = (int)strlen(sequence_of(names[0]));
    int profile[4][501] = {{0}};
    int i, j, k, best, mask;
    const char *symbols[] = {
        "", "A", "C", "M", "G", "R", "S", "V",
        "T", "W", "Y", "H", "K", "D", "B", "N"
    };
    const char *bases = "ACGT";
    char consensus_seq[501], ambiguous[501];
    for (i = 1; i < count; ++i) {
        if (strlen(sequence_of(names[i])) != (size_t)n) {
            fail("length mismatch");
            return;
        }
    }
    for (j = 0; j < n; ++j) {
        for (i = 0; i < count; ++i) {
            const char *base = strchr(bases, sequence_of(names[i])[j]);
            ++profile[base - bases][j];
        }
        best = 0;
        for (k = 0; k < 4; ++k)
            if (profile[k][j] > best) best = profile[k][j];
        mask = 0;
        for (k = 0; k < 4; ++k)
            if (profile[k][j] == best) mask |= 1 << k;
        for (k = 0; k < 4; ++k) {
            if (mask & (1 << k)) {
                consensus_seq[j] = bases[k];
                break;
            }
        }
        ambiguous[j] = symbols[mask][0];
    }
    consensus_seq[n] = '\0';
    ambiguous[n] = '\0';
    for (k = 0; k < 4; ++k) {
        printf("%c", bases[k]);
        for (j = 0; j < n; ++j) printf(" %d", profile[k][j]);
        putchar('\n');
    }
    printf("consensus %s\niupac %s\n", consensus_seq, ambiguous);
}

static void primer(const char *sequence) {
    int n = (int)strlen(sequence), amount = gc(sequence), tm = temperature(sequence);
    int clamp = gc(sequence + (n > 5 ? n - 5 : 0));
    int run = 0, longest = 0, repeated = 0, selfcomp;
    int i, candidate, passed[7];
    const char *labels[] = {"length", "gc", "tm", "clamp", "run", "repeat", "selfcomp"};
    char percentage_text[32], temperature_text[32], values[7][32];
    int failures = 0;
    for (i = 0; i < n; ++i) {
        if (i > 0 && sequence[i] == sequence[i - 1]) ++run;
        else run = 1;
        if (run > longest) longest = run;
    }
    for (i = 0; i + 1 < n; ++i) {
        if (sequence[i] != sequence[i + 1]) {
            candidate = repeat_count(sequence, i, 2);
            if (candidate > repeated) repeated = candidate;
        }
    }
    selfcomp = palindrome_length(sequence);
    percentage(amount, n, percentage_text);
    fixed(tm, 1, temperature_text);
    sprintf(values[0], "%d", n);
    strcpy(values[1], percentage_text);
    strcpy(values[2], temperature_text);
    sprintf(values[3], "%d", clamp);
    sprintf(values[4], "%d", longest);
    sprintf(values[5], "%d", repeated);
    sprintf(values[6], "%d", selfcomp);
    passed[0] = n >= 18 && n <= 25;
    passed[1] = 40 * n <= 100 * amount && 100 * amount <= 60 * n;
    passed[2] = tm >= 520 && tm <= 620;
    passed[3] = clamp >= 1 && clamp <= 3;
    passed[4] = longest <= 4;
    passed[5] = repeated <= 4;
    passed[6] = selfcomp <= 6;
    for (i = 0; i < 7; ++i) {
        printf("%s %s %s\n", labels[i], values[i], passed[i] ? "OK" : "FAIL");
        if (!passed[i]) ++failures;
    }
    if (!failures) puts("PASS");
    else {
        printf("FAIL");
        for (i = 0; i < 7; ++i)
            if (!passed[i]) printf(" %s", labels[i]);
        putchar('\n');
    }
}

static int fold_table[101][101];

static int fold_value(int i, int j) {
    return i > j ? 0 : fold_table[i][j];
}

static int can_pair(char a, char b) {
    return (a == 'A' && b == 'T') || (a == 'T' && b == 'A') ||
           (a == 'C' && b == 'G') || (a == 'G' && b == 'C') ||
           (a == 'G' && b == 'T') || (a == 'T' && b == 'G');
}

static void fold(const char *sequence, int loop) {
    int n = (int)strlen(sequence), width, i, j, k, best;
    int pending_i[201], pending_j[201], pending_count = 0;
    char structure[101];
    if (n > 100) {
        fail("too long");
        return;
    }
    memset(fold_table, 0, sizeof(fold_table));
    memset(structure, '.', (size_t)n);
    structure[n] = '\0';
    for (width = 2; width <= n; ++width) {
        for (i = 0; i + width <= n; ++i) {
            j = i + width - 1;
            best = fold_value(i, j - 1);
            for (k = i; k < j - loop; ++k)
                if (can_pair(sequence[k], sequence[j])) {
                    int candidate = fold_value(i, k - 1) + 1 + fold_value(k + 1, j - 1);
                    if (candidate > best) best = candidate;
                }
            fold_table[i][j] = best;
        }
    }
    pending_i[pending_count] = 0;
    pending_j[pending_count++] = n - 1;
    while (pending_count > 0) {
        --pending_count;
        i = pending_i[pending_count];
        j = pending_j[pending_count];
        if (i > j || fold_value(i, j) == 0) continue;
        if (fold_value(i, j) == fold_value(i, j - 1)) {
            pending_i[pending_count] = i;
            pending_j[pending_count++] = j - 1;
            continue;
        }
        for (k = i; k < j - loop; ++k)
            if (can_pair(sequence[k], sequence[j]) &&
                fold_value(i, k - 1) + 1 + fold_value(k + 1, j - 1) ==
                    fold_value(i, j)) {
                structure[k] = '(';
                structure[j] = ')';
                pending_i[pending_count] = i;
                pending_j[pending_count++] = k - 1;
                pending_i[pending_count] = k + 1;
                pending_j[pending_count++] = j - 1;
                break;
            }
    }
    printf("%s\npairs %d\n", structure, fold_table[0][n - 1]);
}

static void assemble(const char *name, int minimum, int input_count, char **input) {
    char fragments[8][MAX_FRAGMENT + 1];
    char reduced[8][MAX_FRAGMENT + 1];
    char merged[MAX_FRAGMENT + 1];
    int count = 0, i, j, k, best, first, second, limit, width, overlap;
    int reduced_count;
    for (i = 0; i < input_count; ++i) {
        int exists = 0;
        for (j = 0; j < count; ++j)
            if (strcmp(fragments[j], sequence_of(input[i])) == 0) exists = 1;
        if (!exists) strcpy(fragments[count++], sequence_of(input[i]));
    }
    reduced_count = 0;
    for (i = 0; i < count; ++i) {
        int contained = 0;
        for (j = 0; j < count; ++j) {
            if (i != j && strcmp(fragments[i], fragments[j]) != 0 &&
                strstr(fragments[j], fragments[i])) {
                contained = 1;
                break;
            }
        }
        if (!contained) strcpy(reduced[reduced_count++], fragments[i]);
    }
    count = reduced_count;
    for (i = 0; i < count; ++i) strcpy(fragments[i], reduced[i]);
    while (count >= 2) {
        best = 0;
        first = second = -1;
        for (i = 0; i < count; ++i) {
            for (j = 0; j < count; ++j) {
                if (i == j) continue;
                limit = (int)strlen(fragments[i]);
                if ((int)strlen(fragments[j]) < limit)
                    limit = (int)strlen(fragments[j]);
                overlap = 0;
                for (width = limit - 1; width >= 1; --width) {
                    if (strncmp(fragments[i] + strlen(fragments[i]) - width,
                                fragments[j], (size_t)width) == 0) {
                        overlap = width;
                        break;
                    }
                }
                if (first < 0 || overlap > best) {
                    best = overlap;
                    first = i;
                    second = j;
                }
            }
        }
        if (best < minimum) break;
        strcpy(merged, fragments[first]);
        strcat(merged, fragments[second] + best);
        reduced_count = 0;
        for (k = 0; k < count; ++k) {
            if (k == first) strcpy(reduced[reduced_count++], merged);
            else if (k != second && !strstr(merged, fragments[k]))
                strcpy(reduced[reduced_count++], fragments[k]);
        }
        count = reduced_count;
        for (k = 0; k < count; ++k) strcpy(fragments[k], reduced[k]);
    }
    first = 0;
    for (i = 1; i < count; ++i)
        if (strlen(fragments[i]) > strlen(fragments[first])) first = i;
    if (strlen(fragments[first]) > MAX_LENGTH) {
        fail("too long");
        return;
    }
    {
        int existing = exists(name);
        char registration[128];
        sprintf(registration, "%s %s %zu nt",
                existing >= 0 ? "replaced" : "stored", name, strlen(fragments[first]));
        if (existing < 0) {
            existing = sequence_count++;
            strcpy(registry[existing].name, name);
        }
        strcpy(registry[existing].sequence, fragments[first]);
        printf("contigs %d\n", count);
        for (i = 0; i < count; ++i)
            printf("%zu %s\n", strlen(fragments[i]), fragments[i]);
        puts(registration);
    }
}

static void pack(const char *sequence) {
    const char *hex = "0123456789ABCDEF";
    const char *bases = "ACGT";
    int n = (int)strlen(sequence), i, j, value, codes[504] = {0};
    for (i = 0; i < n; ++i) codes[i] = (int)(strchr(bases, sequence[i]) - bases);
    printf("%d ", n);
    for (i = 0; i < n; i += 4) {
        value = 0;
        for (j = 0; j < 4; ++j) value = value * 4 + codes[i + j];
        putchar(hex[value / 16]);
        putchar(hex[value % 16]);
    }
    putchar('\n');
}

static int hex_digit(char c) {
    return c >= '0' && c <= '9' ? c - '0' : c - 'A' + 10;
}

static void unpack(const char *name, int count, const char *hex) {
    char sequence[501];
    int codes[504], code_count = 0, i, value, j;
    for (i = 0; hex[i]; i += 2) {
        value = 16 * hex_digit(hex[i]) + hex_digit(hex[i + 1]);
        codes[code_count++] = value / 64;
        codes[code_count++] = value / 16 % 4;
        codes[code_count++] = value / 4 % 4;
        codes[code_count++] = value % 4;
    }
    for (i = count; i < code_count; ++i) {
        if (codes[i] != 0) {
            fail("invalid padding");
            return;
        }
    }
    for (j = 0; j < count; ++j) sequence[j] = "ACGT"[codes[j]];
    sequence[count] = '\0';
    (void)store(name, sequence);
}

static int compare_names(const void *a, const void *b) {
    const int first = *(const int *)a, second = *(const int *)b;
    return strcmp(registry[first].name, registry[second].name);
}

static void run(const char *command, int argc, char **a) {
    char sequence[MAX_FRAGMENT + 1], other[MAX_FRAGMENT + 1], temp[MAX_FRAGMENT + 1];
    int i, j, k, n, first, last, width, step, positions[501], count;
    if (strcmp(command, "SEQ") == 0) {
        (void)store(a[0], a[1]);
        return;
    }
    if (strcmp(command, "UNPACK") == 0) {
        unpack(a[0], atoi(a[1]), a[2]);
        return;
    }
    if (strcmp(command, "JOIN") == 0) {
        sequence[0] = '\0';
        for (i = 1; i < argc; ++i) strcat(sequence, sequence_of(a[i]));
        (void)store(a[0], sequence);
        return;
    }
    if (strcmp(command, "ASSEMBLE") == 0) {
        assemble(a[0], atoi(a[1]), argc - 2, a + 2);
        return;
    }
    if (strcmp(command, "LIST") == 0) {
        int order[MAX_SEQUENCES];
        for (i = 0; i < sequence_count; ++i) order[i] = i;
        qsort(order, (size_t)sequence_count, sizeof(*order), compare_names);
        if (!sequence_count) puts("no sequences");
        for (i = 0; i < sequence_count; ++i) {
            const Sequence *entry = &registry[order[i]];
            printf("%s %zu nt\n", entry->name, strlen(entry->sequence));
        }
        return;
    }
    strcpy(sequence, sequence_of(a[0]));
    n = (int)strlen(sequence);
    if (strcmp(command, "SLICE") == 0) {
        first = atoi(a[1]);
        last = atoi(a[2]);
        if (first <= last) {
            memcpy(other, sequence + first - 1, (size_t)(last - first + 1));
            other[last - first + 1] = '\0';
        } else {
            memcpy(temp, sequence + last - 1, (size_t)(first - last + 1));
            temp[first - last + 1] = '\0';
            revcomp(temp, other);
        }
        (void)store(a[3], other);
    } else if (strcmp(command, "MUTATE") == 0) {
        int position = atoi(a[1]);
        char before = sequence[position - 1], after = a[2][0];
        if (before == after) {
            fail("no change");
            return;
        }
        sequence[position - 1] = after;
        strcpy(registry[exists(a[0])].sequence, sequence);
        printf("%s %c%d%c %s\n", a[0], before, position, after,
               transition(before, after) ? "transition" : "transversion");
    } else if (strcmp(command, "DEL") == 0) {
        i = exists(a[0]);
        for (j = i; j < sequence_count - 1; ++j) registry[j] = registry[j + 1];
        --sequence_count;
        printf("deleted %s\n", a[0]);
    } else if (strcmp(command, "REVCOMP") == 0) {
        revcomp(sequence, other);
        puts(other);
    } else if (strcmp(command, "COMPLEMENT") == 0) {
        for (i = 0; i < n; ++i) sequence[i] = complement(sequence[i]);
        puts(sequence);
    } else if (strcmp(command, "REVERSE") == 0) {
        for (i = 0; i < n / 2; ++i) {
            char letter = sequence[i];
            sequence[i] = sequence[n - i - 1];
            sequence[n - i - 1] = letter;
        }
        puts(sequence);
    } else if (strcmp(command, "TRANSCRIBE") == 0) {
        for (i = 0; i < n; ++i)
            if (sequence[i] == 'T') sequence[i] = 'U';
        puts(sequence);
    } else if (strcmp(command, "TRANSLATE") == 0 ||
               strcmp(command, "CODONS") == 0 ||
               strcmp(command, "PROTEIN") == 0) {
        translation(sequence, command, atoi(a[1]));
    } else if (strcmp(command, "ORFS") == 0) {
        orfs(sequence, atoi(a[1]));
    } else if (strcmp(command, "GC") == 0) {
        int values[4] = {0};
        char text[32];
        for (i = 0; i < n; ++i)
            ++values[strchr("ACGT", sequence[i]) - "ACGT"];
        percentage(gc(sequence), n, text);
        printf("A=%d C=%d G=%d T=%d GC=%s%%\n",
               values[0], values[1], values[2], values[3], text);
    } else if (strcmp(command, "GCWINDOW") == 0) {
        char text[32];
        width = atoi(a[1]);
        step = atoi(a[2]);
        if (width > n) {
            fail("window too large");
            return;
        }
        for (i = 0; i + width <= n; i += step) {
            memcpy(other, sequence + i, (size_t)width);
            other[width] = '\0';
            percentage(gc(other), width, text);
            printf("%d-%d %s%%\n", i + 1, i + width, text);
        }
    } else if (strcmp(command, "SKEW") == 0) {
        int values[501], minimum = 0, maximum = 0;
        values[0] = 0;
        for (i = 0; i < n; ++i) {
            values[i + 1] = values[i] +
                (sequence[i] == 'G') - (sequence[i] == 'C');
            if (values[i + 1] < minimum) minimum = values[i + 1];
            if (values[i + 1] > maximum) maximum = values[i + 1];
        }
        for (k = 0; k < 2; ++k) {
            int target = k == 0 ? minimum : maximum;
            printf("%s %d at", k == 0 ? "min" : "max", target);
            for (i = 0; i <= n; ++i)
                if (values[i] == target) printf(" %d", i);
            putchar('\n');
        }
    } else if (strcmp(command, "KMERS") == 0) {
        typedef struct {char word[13]; int count;} Kmer;
        Kmer table[500];
        int used = 0, limit, best;
        width = atoi(a[1]);
        limit = atoi(a[2]);
        if (width > n) {
            fail("k too large");
            return;
        }
        for (i = 0; i + width <= n; ++i) {
            memcpy(other, sequence + i, (size_t)width);
            other[width] = '\0';
            for (j = 0; j < used; ++j)
                if (strcmp(table[j].word, other) == 0) break;
            if (j == used) {
                strcpy(table[used].word, other);
                table[used++].count = 0;
            }
            ++table[j].count;
        }
        printf("%d windows %d distinct\n", n - width + 1, used);
        for (i = 0; i < limit && i < used; ++i) {
            best = -1;
            for (j = 0; j < used; ++j) {
                if (table[j].count <= 0) continue;
                if (best < 0 || table[j].count > table[best].count ||
                    (table[j].count == table[best].count &&
                     strcmp(table[j].word, table[best].word) < 0))
                    best = j;
            }
            printf("%s %d\n", table[best].word, table[best].count);
            table[best].count = 0;
        }
    } else if (strcmp(command, "FIND") == 0) {
        count = occurrences(sequence, a[1], positions);
        print_list("forward", positions, count);
        revcomp(a[1], other);
        count = occurrences(sequence, other, positions);
        print_list("reverse", positions, count);
    } else if (strcmp(command, "RESTRICT") == 0) {
        restriction(sequence, argc - 1, a + 1);
    } else if (strcmp(command, "PALINDROMES") == 0) {
        int minimum = atoi(a[1]), maximum = atoi(a[2]), found = 0;
        if (minimum > maximum) {
            fail("invalid range");
            return;
        }
        for (i = 0; i < n; ++i) {
            for (width = minimum; width <= maximum && i + width <= n; ++width) {
                memcpy(other, sequence + i, (size_t)width);
                other[width] = '\0';
                revcomp(other, temp);
                if (strcmp(other, temp) == 0) {
                    printf("%d %d %s\n", i + 1, width, other);
                    found = 1;
                }
            }
        }
        if (!found) puts("none");
    } else if (strcmp(command, "REPEATS") == 0) {
        repeats(sequence, atoi(a[1]), atoi(a[2]), atoi(a[3]));
    } else if (strcmp(command, "HAMMING") == 0) {
        const char *second = sequence_of(a[1]);
        int distance = 0, changes = 0;
        if (strlen(second) != (size_t)n) {
            fail("length mismatch");
            return;
        }
        for (i = 0; i < n; ++i) {
            if (sequence[i] != second[i]) {
                ++distance;
                changes += transition(sequence[i], second[i]);
            }
        }
        printf("distance %d transitions %d transversions %d\n",
               distance, changes, distance - changes);
    } else if (strcmp(command, "ALIGN") == 0) {
        alignment(sequence, sequence_of(a[1]), a[2],
                  atoi(a[3]), atoi(a[4]), atoi(a[5]));
    } else if (strcmp(command, "CONSENSUS") == 0) {
        consensus(argc, a);
    } else if (strcmp(command, "TM") == 0) {
        char text[32];
        fixed(temperature(sequence), 1, text);
        printf("Tm %s %s\n", text, n < 14 ? "wallace" : "gc");
    } else if (strcmp(command, "MASS") == 0) {
        char single[32], twice[32];
        int mass = strand_mass(sequence);
        revcomp(sequence, other);
        fixed(mass, 3, single);
        fixed(mass + strand_mass(other), 3, twice);
        printf("ss %s ds %s\n", single, twice);
    } else if (strcmp(command, "PRIMER") == 0) {
        primer(sequence);
    } else if (strcmp(command, "FOLD") == 0) {
        fold(sequence, atoi(a[1]));
    } else if (strcmp(command, "PACK") == 0) {
        pack(sequence);
    }
}

int main(void) {
    char line[MAX_LINE], *words[16], *token, *command;
    int commands, i, count;
    if (!fgets(line, sizeof(line), stdin)) return 0;
    commands = atoi(line);
    for (i = 0; i < commands; ++i) {
        if (!fgets(line, sizeof(line), stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        count = 0;
        token = strtok(line, " ");
        command = token;
        while ((token = strtok(NULL, " ")) != NULL)
            words[count++] = token;
        error_message[0] = '\0';
        if (validate(command, count, words)) run(command, count, words);
        if (error_message[0]) printf("ERROR %s\n", error_message);
    }
    return 0;
}
