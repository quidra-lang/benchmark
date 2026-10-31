#include "cipher.h"
#include <errno.h>
#include <sys/stat.h>

typedef enum {
    ENCRYPT, DECRYPT, BREAK, ANALYZE, COMPARE, IDENTIFY, COMMAND_COUNT
} Command;

static const char *const command_names[] = {
    "ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY"
};

static const char *const cipher_names[] = {
    "caesar", "affine", "vigenere", "autokey", "playfair", "railfence", "columnar"
};

static const int multipliers[] = {1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25};

typedef struct {
    char *data;
    size_t length;
    size_t capacity;
} Buffer;

typedef struct {
    char name[17];
    char *body;
} Message;

typedef struct {
    int top;
    int max_length;
    int ioc;
    int kasiski;
    int refine;
    int max_rails;
    const char *keys;
} Options;

typedef struct {
    Command command;
    Cipher cipher;
    char *key;
    const char *source;
    const char *second;
    const char *new_name;
    Options options;
} Job;

typedef struct {
    char **items;
    int count;
    int capacity;
} KeyList;

typedef struct {
    char *key;
    int score;
    int order;
    char preview[41];
} Candidate;

typedef struct {
    Candidate *candidates;
    int count;
    int capacity;
    char *key;
    int score;
    Profile *profile;
    int length;
    const char *method;
    int passes;
    int changes;
} BreakResult;

typedef struct {
    Weights weights;
    Message *messages;
    int message_count;
    int message_capacity;
    int jobs;
    int ok[COMMAND_COUNT];
    int errors[COMMAND_COUNT];
    FILE *results;
    FILE *candidates;
    FILE *analysis;
} Desk;

static void *resize(void *pointer, size_t size) {
    void *result = realloc(pointer, size);
    if (!result)
        exit(EXIT_FAILURE);
    return result;
}

static char *copy_text(const char *text) {
    char *result = resize(NULL, strlen(text) + 1);
    strcpy(result, text);
    return result;
}

static void append(Buffer *buffer, const char *text) {
    size_t length = strlen(text);
    size_t needed = buffer->length + length + 1;
    if (needed > buffer->capacity) {
        size_t capacity = buffer->capacity ? buffer->capacity : 64;
        while (capacity < needed)
            capacity *= 2;
        buffer->data = resize(buffer->data, capacity);
        buffer->capacity = capacity;
    }
    memcpy(buffer->data + buffer->length, text, length + 1);
    buffer->length += length;
}

static char *read_line(FILE *file) {
    Buffer buffer = {0};
    int character;
    while ((character = fgetc(file)) != EOF && character != '\n') {
        char part[2] = {(char)character, '\0'};
        append(&buffer, part);
    }
    if (!buffer.data) {
        if (character == EOF)
            return NULL;
        return copy_text("");
    }
    return buffer.data;
}

static Message *find_message(Desk *desk, const char *name) {
    for (int i = 0; i < desk->message_count; ++i)
        if (strcmp(desk->messages[i].name, name) == 0)
            return &desk->messages[i];
    return NULL;
}

static void store_message(Desk *desk, const char *name, const char *body) {
    char *saved_body = copy_text(body);
    if (desk->message_count == desk->message_capacity) {
        desk->message_capacity = desk->message_capacity ? desk->message_capacity * 2 : 64;
        desk->messages = resize(desk->messages,
                                (size_t)desk->message_capacity * sizeof(*desk->messages));
    }
    Message *message = &desk->messages[desk->message_count++];
    strcpy(message->name, name);
    message->body = saved_body;
}

static bool read_messages(Desk *desk) {
    FILE *file = fopen("input/messages.txt", "r");
    if (!file)
        return false;
    char *line;
    while ((line = read_line(file))) {
        if (!*line) {
            free(line);
            continue;
        }
        char name[17];
        strcpy(name, line + 8);
        free(line);
        Buffer body = {0};
        int lines = 0;
        while ((line = read_line(file))) {
            if (strcmp(line, "END") == 0) {
                free(line);
                break;
            }
            if (lines++)
                append(&body, "\n");
            append(&body, line);
            free(line);
        }
        store_message(desk, name, body.data ? body.data : "");
        free(body.data);
    }
    fclose(file);
    return true;
}

static bool valid_name(const char *text) {
    size_t length = strlen(text);
    if (length < 1 || length > 16)
        return false;
    for (; *text; ++text)
        if (!(*text >= 'a' && *text <= 'z') &&
            !(*text >= '0' && *text <= '9') && *text != '_')
            return false;
    return true;
}

static bool digit_string(const char *text, int max_length) {
    size_t length = strlen(text);
    if (!length || length > (size_t)max_length)
        return false;
    for (; *text; ++text)
        if (*text < '0' || *text > '9')
            return false;
    return true;
}

static bool valid_multiplier(int value) {
    for (int i = 0; i < 12; ++i)
        if (multipliers[i] == value)
            return true;
    return false;
}

static char *parse_key(Cipher cipher, const char *word) {
    size_t length = strlen(word);
    char buffer[32];
    if (cipher == CAESAR || cipher == RAILFENCE) {
        int minimum = cipher == CAESAR ? 0 : 2;
        int maximum = cipher == CAESAR ? 25 : 20;
        if (!digit_string(word, 2) || atoi(word) < minimum || atoi(word) > maximum)
            return NULL;
        snprintf(buffer, sizeof(buffer), "%d", atoi(word));
        return copy_text(buffer);
    }
    if (cipher == AFFINE) {
        const char *comma = strchr(word, ',');
        if (!comma || strchr(comma + 1, ',') || comma == word || comma - word > 2)
            return NULL;
        char first[3];
        size_t size = (size_t)(comma - word);
        memcpy(first, word, size);
        first[size] = '\0';
        if (!digit_string(first, 2) || !digit_string(comma + 1, 2))
            return NULL;
        int a = atoi(first), b = atoi(comma + 1);
        if (!valid_multiplier(a) || b > 25)
            return NULL;
        snprintf(buffer, sizeof(buffer), "%d,%d", a, b);
        return copy_text(buffer);
    }
    int minimum = cipher == COLUMNAR ? 2 : 1;
    int maximum = cipher == COLUMNAR ? 9 : cipher == PLAYFAIR ? 25 : 20;
    if (length < (size_t)minimum || length > (size_t)maximum)
        return NULL;
    char *key = copy_text(word);
    for (size_t i = 0; i < length; ++i) {
        int value = letter_value(word[i]);
        if (value < 0) {
            if (cipher != COLUMNAR || word[i] < '0' || word[i] > '9') {
                free(key);
                return NULL;
            }
        } else {
            key[i] = (char)('A' + value);
            if (cipher == PLAYFAIR && key[i] == 'J')
                key[i] = 'I';
        }
    }
    return key;
}

static Options default_options(Cipher cipher) {
    Options options = {5, 10, 6000, 60, 5, 10, NULL};
    if (cipher == AUTOKEY)
        options.max_length = 8;
    if (cipher == COLUMNAR)
        options.max_length = 6;
    return options;
}

static bool fail(char *reason, const char *message, const char *word) {
    if (word)
        snprintf(reason, 256, "%s %s", message, word);
    else
        snprintf(reason, 256, "%s", message);
    return false;
}

static bool parse_options(Job *job, char **words, int first, int count, char *reason) {
    static const char *const names[] = {
        "TOP", "MAXLEN", "IOC", "KASISKI", "REFINE", "MAXRAILS", "KEYS"
    };
    unsigned seen = 0;
    for (int i = first; i < count; ++i) {
        const char *word = words[i];
        const char *equal = strchr(word, '=');
        int option = -1;
        if (equal)
            for (int j = 0; j < 7; ++j)
                if ((size_t)(equal - word) == strlen(names[j]) &&
                    strncmp(word, names[j], (size_t)(equal - word)) == 0)
                    option = j;
        if (option < 0 || (seen & (1u << option)))
            return fail(reason, "bad option", word);
        bool allowed = false;
        int minimum = 0, maximum = 0;
        if (option == 0) {
            allowed = job->command == BREAK;
            minimum = 1;
            maximum = 20;
        } else if (option == 1) {
            allowed = job->command == ANALYZE ||
                      (job->command == BREAK &&
                       (job->cipher == VIGENERE || job->cipher == AUTOKEY ||
                        job->cipher == COLUMNAR));
            minimum = job->cipher == AUTOKEY && job->command == BREAK ? 1 : 2;
            maximum = job->cipher == COLUMNAR && job->command == BREAK ? 6 : 20;
        } else if (option >= 2 && option <= 4) {
            allowed = job->command == BREAK && job->cipher == VIGENERE;
            minimum = option == 4 ? 0 : 1;
            maximum = option == 2 ? 100000 : option == 3 ? 100 : 10;
        } else if (option == 5) {
            allowed = job->command == BREAK && job->cipher == RAILFENCE;
            minimum = 2;
            maximum = 20;
        } else
            allowed = job->command == IDENTIFY ||
                      (job->command == BREAK && job->cipher == PLAYFAIR);
        if (!allowed)
            return fail(reason, "bad option", word);
        const char *value = equal + 1;
        if (option == 6) {
            if (!valid_name(value))
                return fail(reason, "bad option", word);
            job->options.keys = value;
        } else {
            if (!digit_string(value, 6))
                return fail(reason, "bad option", word);
            int number = atoi(value);
            if (number < minimum || number > maximum)
                return fail(reason, "bad option", word);
            switch (option) {
                case 0: job->options.top = number; break;
                case 1: job->options.max_length = number; break;
                case 2: job->options.ioc = number; break;
                case 3: job->options.kasiski = number; break;
                case 4: job->options.refine = number; break;
                case 5: job->options.max_rails = number; break;
            }
        }
        seen |= 1u << option;
    }
    if (job->command == BREAK && job->cipher == PLAYFAIR && !job->options.keys)
        return fail(reason, "missing option KEYS", NULL);
    return true;
}

static bool validate_job(Desk *desk, Job *job, char **words, int count, char *reason) {
    if (job->command <= BREAK && count >= 5 && strcmp(words[count - 2], "AS") == 0) {
        job->new_name = words[count - 1];
        if (!valid_name(job->new_name))
            return fail(reason, "bad syntax", NULL);
        count -= 2;
    }
    bool valid_count;
    if (job->command == ENCRYPT || job->command == DECRYPT)
        valid_count = count == 4;
    else if (job->command == BREAK)
        valid_count = count >= 3;
    else if (job->command == ANALYZE || job->command == IDENTIFY)
        valid_count = count == 2 || count == 3;
    else
        valid_count = count == 3;
    if (!valid_count)
        return fail(reason, "bad syntax", NULL);
    if (job->command <= BREAK) {
        job->cipher = CIPHER_COUNT;
        for (int i = 0; i < CIPHER_COUNT; ++i)
            if (strcmp(words[1], cipher_names[i]) == 0)
                job->cipher = (Cipher)i;
        if (job->cipher == CIPHER_COUNT)
            return fail(reason, "unknown cipher", words[1]);
    }
    if (job->command == ENCRYPT || job->command == DECRYPT) {
        job->key = parse_key(job->cipher, words[2]);
        if (!job->key)
            return fail(reason, "bad key", words[2]);
        job->source = words[3];
    } else if (job->command == BREAK)
        job->source = words[2];
    else
        job->source = words[1];
    job->options = default_options(job->cipher);
    if (job->command == BREAK || job->command == ANALYZE || job->command == IDENTIFY) {
        int first = job->command == BREAK ? 3 : 2;
        if (!parse_options(job, words, first, count, reason))
            return false;
    }
    if (!find_message(desk, job->source))
        return fail(reason, "unknown message", job->source);
    if (job->command == COMPARE) {
        job->second = words[2];
        if (!find_message(desk, job->second))
            return fail(reason, "unknown message", job->second);
    } else if (job->options.keys && !find_message(desk, job->options.keys))
        return fail(reason, "unknown message", job->options.keys);
    if (job->new_name && find_message(desk, job->new_name))
        return fail(reason, "duplicate message", job->new_name);
    return true;
}

static char *transform(Cipher cipher, const char *text, const char *key, bool decrypt) {
    if (cipher <= AUTOKEY)
        return substitute(cipher, text, key, decrypt);
    if (cipher == PLAYFAIR)
        return playfair_transform(text, key, decrypt);
    if (cipher == RAILFENCE)
        return rail_fence(text, atoi(key), decrypt);
    return columnar(text, key, decrypt);
}

static char *group_form(const char *letters) {
    size_t length = strlen(letters);
    char *result = resize(NULL, length + length / 5 + 1);
    size_t next = 0;
    for (size_t i = 0; i < length; ++i) {
        if (i && i % 5 == 0)
            result[next++] = i % 50 == 0 ? '\n' : ' ';
        result[next++] = letters[i];
    }
    result[next] = '\0';
    return result;
}

static int line_count(const char *text) {
    int count = 1;
    for (; *text; ++text)
        if (*text == '\n')
            ++count;
    return count;
}

static char *result_body(Cipher cipher, const char *body, const char *letters,
                         const char *key, bool decrypt) {
    char *text = transform(cipher, cipher <= AUTOKEY ? body : letters, key, decrypt);
    if (cipher <= AUTOKEY)
        return text;
    char *grouped = group_form(text);
    free(text);
    return grouped;
}

static void result_suffix(Desk *desk, const Job *job, const char *body) {
    if (job->new_name)
        fprintf(desk->results, " as=%s", job->new_name);
    fprintf(desk->results, "\n%s\n", body);
    if (job->new_name)
        store_message(desk, job->new_name, body);
}

static KeyList build_key_list(const char *body) {
    KeyList keys = {0};
    for (const char *p = body; *p;) {
        if (letter_value(*p) < 0) {
            ++p;
            continue;
        }
        const char *start = p;
        while (letter_value(*p) >= 0)
            ++p;
        size_t length = (size_t)(p - start);
        char *key = resize(NULL, length + 1);
        for (size_t i = 0; i < length; ++i) {
            key[i] = (char)('A' + letter_value(start[i]));
            if (key[i] == 'J')
                key[i] = 'I';
        }
        key[length] = '\0';
        bool duplicate = false;
        for (int i = 0; i < keys.count; ++i)
            if (strcmp(key, keys.items[i]) == 0) {
                duplicate = true;
                break;
            }
        if (duplicate) {
            free(key);
            continue;
        }
        if (keys.count == keys.capacity) {
            keys.capacity = keys.capacity ? keys.capacity * 2 : 16;
            keys.items = resize(keys.items, (size_t)keys.capacity * sizeof(*keys.items));
        }
        keys.items[keys.count++] = key;
    }
    return keys;
}

static void free_key_list(KeyList *keys) {
    for (int i = 0; i < keys->count; ++i)
        free(keys->items[i]);
    free(keys->items);
}

static void add_candidate(Desk *desk, BreakResult *result, Cipher cipher,
                          const char *letters, const char *key) {
    if (result->count == result->capacity) {
        result->capacity = result->capacity ? result->capacity * 2 : 32;
        result->candidates = resize(result->candidates,
                                    (size_t)result->capacity * sizeof(*result->candidates));
    }
    char *plaintext = transform(cipher, letters, key, true);
    Candidate *candidate = &result->candidates[result->count];
    candidate->key = copy_text(key);
    candidate->score = cipher == CAESAR || cipher == AFFINE
                       ? monogram_fitness(&desk->weights, plaintext)
                       : bigram_fitness(&desk->weights, plaintext);
    candidate->order = result->count++;
    memcpy(candidate->preview, plaintext, 40);
    candidate->preview[40] = '\0';
    free(plaintext);
}

static void columnar_candidates(Desk *desk, BreakResult *result, const char *letters,
                                char *key, int width, int position, unsigned used) {
    if (position == width) {
        key[width] = '\0';
        add_candidate(desk, result, COLUMNAR, letters, key);
        return;
    }
    for (int digit = 1; digit <= width; ++digit)
        if (!(used & (1u << digit))) {
            key[position] = (char)('0' + digit);
            columnar_candidates(desk, result, letters, key, width, position + 1,
                                used | (1u << digit));
        }
}

static void column_key(Desk *desk, Cipher cipher, const char *letters,
                        int period, char *key) {
    int length = (int)strlen(letters);
    for (int column = 0; column < period; ++column) {
        int best_shift = 0, best_score = -1;
        for (int shift = 0; shift < 26; ++shift) {
            int score = 0, previous = shift;
            for (int i = column; i < length; i += period) {
                int value = (letters[i] - 'A' - previous + 26) % 26;
                score += desk->weights.mono[value];
                if (cipher == AUTOKEY)
                    previous = value;
            }
            if (score > best_score) {
                best_score = score;
                best_shift = shift;
            }
        }
        key[column] = (char)('A' + best_shift);
    }
    key[period] = '\0';
}

static int compare_candidates(const void *left, const void *right) {
    const Candidate *a = left;
    const Candidate *b = right;
    if (a->score != b->score)
        return a->score > b->score ? -1 : 1;
    return (a->order > b->order) - (a->order < b->order);
}

static int vigenere_score(Desk *desk, const char *letters, const char *key) {
    char *plaintext = substitute(VIGENERE, letters, key, true);
    int score = bigram_fitness(&desk->weights, plaintext);
    free(plaintext);
    return score;
}

static void refine_vigenere(Desk *desk, BreakResult *result, const char *letters,
                            const Options *options) {
    result->profile = analyze_periods(letters, options->max_length);
    Profile *profile = result->profile;
    int kasiski_length = 0;
    if (profile->gap_count)
        for (int period = 2; period <= options->max_length; ++period)
            if (100 * profile->kasiski[period] >= options->kasiski * profile->gap_count)
                kasiski_length = period;
    if (kasiski_length && profile->averages[kasiski_length] >= options->ioc) {
        result->length = kasiski_length;
        result->method = "kasiski";
    } else {
        for (int period = 1; period <= options->max_length; ++period)
            if (profile->averages[period] >= options->ioc) {
                result->length = period;
                result->method = "ioc";
                break;
            }
        if (!result->length) {
            result->length = 1;
            result->method = "maxioc";
            for (int period = 2; period <= options->max_length; ++period)
                if (profile->averages[period] > profile->averages[result->length])
                    result->length = period;
        }
    }
    Candidate *candidate = &result->candidates[result->length - 1];
    result->key = copy_text(candidate->key);
    result->score = candidate->score;
    while (result->passes < options->refine) {
        ++result->passes;
        bool changed = false;
        for (int column = 0; column < result->length; ++column) {
            char original = result->key[column], best_letter = 'A';
            int best_score = -1;
            for (char letter = 'A'; letter <= 'Z'; ++letter) {
                result->key[column] = letter;
                int score = vigenere_score(desk, letters, result->key);
                if (score > best_score) {
                    best_score = score;
                    best_letter = letter;
                }
            }
            if (best_score > result->score) {
                result->key[column] = best_letter;
                result->score = best_score;
                ++result->changes;
                changed = true;
            } else
                result->key[column] = original;
        }
        if (!changed)
            break;
    }
}

static BreakResult break_cipher(Desk *desk, Cipher cipher, const char *letters,
                                 const Options *options, const KeyList *keys) {
    BreakResult result = {0};
    char key[32];
    if (cipher == CAESAR || cipher == RAILFENCE) {
        int minimum = cipher == CAESAR ? 0 : 2;
        int maximum = cipher == CAESAR ? 25 : options->max_rails;
        for (int value = minimum; value <= maximum; ++value) {
            snprintf(key, sizeof(key), "%d", value);
            add_candidate(desk, &result, cipher, letters, key);
        }
    } else if (cipher == AFFINE) {
        for (int i = 0; i < 12; ++i)
            for (int b = 0; b < 26; ++b) {
                snprintf(key, sizeof(key), "%d,%d", multipliers[i], b);
                add_candidate(desk, &result, cipher, letters, key);
            }
    } else if (cipher == COLUMNAR) {
        for (int width = 2; width <= options->max_length; ++width)
            columnar_candidates(desk, &result, letters, key, width, 0, 0);
    } else if (cipher == PLAYFAIR) {
        for (int i = 0; i < keys->count; ++i)
            add_candidate(desk, &result, cipher, letters, keys->items[i]);
    } else {
        for (int length = 1; length <= options->max_length; ++length) {
            column_key(desk, cipher, letters, length, key);
            add_candidate(desk, &result, cipher, letters, key);
        }
    }
    if (cipher == VIGENERE)
        refine_vigenere(desk, &result, letters, options);
    qsort(result.candidates, (size_t)result.count, sizeof(*result.candidates), compare_candidates);
    if (cipher != VIGENERE) {
        result.key = copy_text(result.candidates[0].key);
        result.score = result.candidates[0].score;
    }
    return result;
}

static void free_break(BreakResult *result) {
    for (int i = 0; i < result->count; ++i)
        free(result->candidates[i].key);
    free(result->candidates);
    free(result->key);
    free_profile(result->profile);
}

static void write_profile(FILE *file, const Profile *profile) {
    for (int period = 1; period <= profile->max_length; ++period) {
        fprintf(file, "L=%d ioc=%d kasiski=%d cols=", period,
                profile->averages[period], profile->kasiski[period]);
        for (int column = 0; column < period; ++column)
            fprintf(file, "%s%d", column ? "," : "", profile->indices[period][column]);
        fputc('\n', file);
    }
    fprintf(file, "kasiski repeats=%d spacings=%d\n", profile->repeat_count, profile->gap_count);
    for (int i = 0; i < profile->repeat_count; ++i) {
        const Repeat *repeat = &profile->repeats[i];
        int code = repeat->code;
        fprintf(file, "%c%c%c at=", 'A' + code / 676, 'A' + code / 26 % 26, 'A' + code % 26);
        for (int j = 0; j < repeat->count; ++j)
            fprintf(file, "%s%d", j ? "," : "", repeat->positions[j]);
        fputs(" gaps=", file);
        for (int j = 1; j < repeat->count; ++j)
            fprintf(file, "%s%d", j > 1 ? "," : "", repeat->positions[j] - repeat->positions[j - 1]);
        fprintf(file, " gcd=%d\n", repeat->gcd);
    }
}

static void write_top_pairs(FILE *file, const char *prefix, const PairCount *pairs, int count) {
    fputs(prefix, file);
    for (int i = 0; i < count && i < 10; ++i)
        fprintf(file, " %c%c:%d", 'A' + pairs[i].pair / 26, 'A' + pairs[i].pair % 26,
                pairs[i].count);
    fputc('\n', file);
}

static void write_break_reports(Desk *desk, const Job *job, const char *letters,
                                const BreakResult *result) {
    int margin = result->count > 1
                 ? result->candidates[0].score - result->candidates[1].score : 0;
    fprintf(desk->candidates, "JOB %d BREAK %s source=%s tried=%d margin=%d\n",
            desk->jobs, cipher_names[job->cipher], job->source, result->count, margin);
    for (int i = 0; i < result->count && i < job->options.top; ++i) {
        const Candidate *candidate = &result->candidates[i];
        fprintf(desk->candidates, "%d %s %d %s\n", i + 1, candidate->key,
                candidate->score, candidate->preview);
    }
    if (job->cipher == VIGENERE) {
        fprintf(desk->analysis, "JOB %d BREAK vigenere source=%s\nletters=%zu\n",
                desk->jobs, job->source, strlen(letters));
        write_profile(desk->analysis, result->profile);
        fprintf(desk->analysis, "decision length=%d method=%s\n", result->length, result->method);
        fprintf(desk->analysis, "refine passes=%d changes=%d key=%s\n",
                result->passes, result->changes, result->key);
    } else if (job->cipher == PLAYFAIR) {
        PairCount pairs[676];
        int distinct = pair_counts(letters, true, pairs);
        fprintf(desk->analysis, "JOB %d BREAK playfair source=%s\nletters=%zu\n",
                desk->jobs, job->source, strlen(letters));
        fprintf(desk->analysis, "digraphs pairs=%zu distinct=%d\n", strlen(letters) / 2, distinct);
        write_top_pairs(desk->analysis, "top", pairs, distinct);
        char square[26];
        playfair_square(result->key, square);
        fputs("square", desk->analysis);
        for (int row = 0; row < 5; ++row)
            fprintf(desk->analysis, " %.5s", square + 5 * row);
        fputc('\n', desk->analysis);
    }
}

static void analyze_message(Desk *desk, const Job *job, const char *letters) {
    int length = (int)strlen(letters), counts[26];
    letter_counts(letters, counts);
    int doubles = 0, pair_doubles = 0, distinct = 0;
    for (int i = 0; i + 1 < length; ++i)
        if (letters[i] == letters[i + 1]) {
            ++doubles;
            if (i % 2 == 0)
                ++pair_doubles;
        }
    for (int i = 0; i < 26; ++i)
        if (counts[i])
            ++distinct;
    fprintf(desk->results, "JOB %d ANALYZE source=%s letters=%d\n", desk->jobs, job->source, length);
    fprintf(desk->analysis, "JOB %d ANALYZE source=%s\nletters=%d\n", desk->jobs, job->source, length);
    fprintf(desk->analysis, "ioc=%d mono=%d bigram=%d\n", index_of_coincidence(letters),
            monogram_fitness(&desk->weights, letters), bigram_fitness(&desk->weights, letters));
    fprintf(desk->analysis, "doubles=%d pair_doubles=%d distinct=%d\n", doubles, pair_doubles, distinct);
    for (int i = 0; i < 26; ++i) {
        char percent[16];
        percentage(counts[i], length, percent);
        fprintf(desk->analysis, "%c %d %s\n", 'A' + i, counts[i], percent);
    }
    PairCount pairs[676];
    int count = pair_counts(letters, false, pairs);
    write_top_pairs(desk->analysis, "bigrams", pairs, count);
    Profile *profile = analyze_periods(letters, job->options.max_length);
    write_profile(desk->analysis, profile);
    free_profile(profile);
}

static void compare_messages(Desk *desk, const Job *job, const char *first) {
    char *second = letter_string(find_message(desk, job->second)->body);
    int a = (int)strlen(first), b = (int)strlen(second);
    fprintf(desk->results, "JOB %d COMPARE %s %s", desk->jobs, job->source, job->second);
    if (strcmp(first, second) == 0)
        fprintf(desk->results, " equal letters=%d\n", a);
    else {
        int shared = a < b ? a : b;
        int first_mismatch = shared + 1, mismatches = 0;
        for (int i = 0; i < shared; ++i)
            if (first[i] != second[i]) {
                if (!mismatches)
                    first_mismatch = i + 1;
                ++mismatches;
            }
        fprintf(desk->results, " differ letters=%d,%d first=%d mismatches=%d\n",
                a, b, first_mismatch, mismatches);
    }
    free(second);
}

static bool identify_message(Desk *desk, const Job *job, const char *body,
                              const char *letters, char *reason) {
    int length = (int)strlen(letters);
    int ioc = index_of_coincidence(letters);
    int average = monogram_fitness(&desk->weights, letters) / length;
    int counts[26], distinct = 0;
    letter_counts(letters, counts);
    for (int i = 0; i < 26; ++i)
        if (counts[i])
            ++distinct;
    bool shape = length % 2 == 0 && !strchr(letters, 'J') && valid_playfair(letters);
    const char *family;
    Cipher ciphers[2];
    int trial_count = 0;
    KeyList keys = {0};
    if (shape) {
        family = "playfair";
        if (job->options.keys) {
            keys = build_key_list(find_message(desk, job->options.keys)->body);
            if (!keys.count) {
                free_key_list(&keys);
                return fail(reason, "empty key list", NULL);
            }
            ciphers[trial_count++] = PLAYFAIR;
        }
    } else if (ioc >= 5500 && average >= 44) {
        family = "transposition";
        ciphers[trial_count++] = RAILFENCE;
        ciphers[trial_count++] = COLUMNAR;
    } else if (ioc >= 5500) {
        family = "monoalphabetic";
        ciphers[trial_count++] = AFFINE;
    } else {
        family = "polyalphabetic";
        ciphers[trial_count++] = VIGENERE;
        ciphers[trial_count++] = AUTOKEY;
    }
    fprintf(desk->analysis, "JOB %d IDENTIFY source=%s\n", desk->jobs, job->source);
    fprintf(desk->analysis, "letters=%d ioc=%d mono_avg=%d distinct=%d shape=%s\n",
            length, ioc, average, distinct, shape ? "yes" : "no");
    fprintf(desk->analysis, "family=%s\n", family);
    BreakResult trials[2];
    int chosen = 0;
    for (int i = 0; i < trial_count; ++i) {
        Options options = default_options(ciphers[i]);
        trials[i] = break_cipher(desk, ciphers[i], letters, &options, &keys);
        fprintf(desk->analysis, "try %s key=%s score=%d\n", cipher_names[ciphers[i]],
                trials[i].key, trials[i].score);
        if (trials[i].score > trials[chosen].score)
            chosen = i;
    }
    fprintf(desk->results, "JOB %d IDENTIFY source=%s family=%s", desk->jobs, job->source, family);
    if (!trial_count)
        fputc('\n', desk->results);
    else {
        Cipher cipher = ciphers[chosen];
        const char *key = trials[chosen].key;
        if (cipher == AFFINE && strncmp(key, "1,", 2) == 0) {
            cipher = CAESAR;
            key += 2;
        }
        char *output = result_body(cipher, body, letters, key, true);
        fprintf(desk->results, " cipher=%s key=%s score=%d lines=%d\n%s\n",
                cipher_names[cipher], key, trials[chosen].score, line_count(output), output);
        fprintf(desk->analysis, "choice %s\n", cipher_names[cipher]);
        free(output);
    }
    for (int i = 0; i < trial_count; ++i)
        free_break(&trials[i]);
    free_key_list(&keys);
    return true;
}

static bool execute_job(Desk *desk, const Job *job, char *reason) {
    const char *body = find_message(desk, job->source)->body;
    char *letters = letter_string(body);
    int length = (int)strlen(letters);
    bool success = true;
    if (job->command == COMPARE)
        compare_messages(desk, job, letters);
    else if (job->command == ENCRYPT || job->command == DECRYPT) {
        bool decrypt = job->command == DECRYPT;
        if (!length)
            success = fail(reason, "no letters", NULL);
        else if (decrypt && job->cipher == PLAYFAIR && !valid_playfair(letters))
            success = fail(reason, "bad playfair text", NULL);
        else {
            char *output = result_body(job->cipher, body, letters, job->key, decrypt);
            char *output_letters = letter_string(output);
            fprintf(desk->results, "JOB %d %s %s key=%s source=%s letters=%zu lines=%d",
                    desk->jobs, command_names[job->command], cipher_names[job->cipher],
                    job->key, job->source, strlen(output_letters), line_count(output));
            result_suffix(desk, job, output);
            free(output_letters);
            free(output);
        }
    } else if (length < 40)
        success = fail(reason, "text too short", NULL);
    else if (job->command == ANALYZE)
        analyze_message(desk, job, letters);
    else if (job->command == IDENTIFY)
        success = identify_message(desk, job, body, letters, reason);
    else {
        KeyList keys = {0};
        if (job->cipher == PLAYFAIR) {
            if (!valid_playfair(letters))
                success = fail(reason, "bad playfair text", NULL);
            else {
                keys = build_key_list(find_message(desk, job->options.keys)->body);
                if (!keys.count)
                    success = fail(reason, "empty key list", NULL);
            }
        }
        if (success) {
            BreakResult result = break_cipher(desk, job->cipher, letters, &job->options, &keys);
            char *output = result_body(job->cipher, body, letters, result.key, true);
            fprintf(desk->results, "JOB %d BREAK %s source=%s key=%s score=%d lines=%d",
                    desk->jobs, cipher_names[job->cipher], job->source,
                    result.key, result.score, line_count(output));
            write_break_reports(desk, job, letters, &result);
            result_suffix(desk, job, output);
            free(output);
            free_break(&result);
        }
        free_key_list(&keys);
    }
    free(letters);
    return success;
}

static void run_job(Desk *desk, char *line) {
    ++desk->jobs;
    char *words[201];
    int count = 0;
    char *word = strtok(line, " ");
    while (word) {
        words[count++] = word;
        word = strtok(NULL, " ");
    }
    Job job = {0};
    job.command = COMMAND_COUNT;
    for (int i = 0; i < COMMAND_COUNT; ++i)
        if (strcmp(words[0], command_names[i]) == 0)
            job.command = (Command)i;
    if (job.command == COMMAND_COUNT) {
        fprintf(desk->results, "JOB %d ERROR unknown command\n", desk->jobs);
        return;
    }
    char reason[256];
    if (validate_job(desk, &job, words, count, reason) && execute_job(desk, &job, reason))
        ++desk->ok[job.command];
    else {
        ++desk->errors[job.command];
        fprintf(desk->results, "JOB %d ERROR %s\n", desk->jobs, reason);
    }
    free(job.key);
}

int main(void) {
    Desk desk = {0};
    if (!read_weights("input/weights.txt", &desk.weights) || !read_messages(&desk))
        return EXIT_FAILURE;
    FILE *jobs = fopen("input/jobs.txt", "r");
    if (!jobs)
        return EXIT_FAILURE;
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        fclose(jobs);
        return EXIT_FAILURE;
    }
    desk.results = fopen("output/results.txt", "w");
    desk.candidates = fopen("output/candidates.txt", "w");
    desk.analysis = fopen("output/analysis.txt", "w");
    if (!desk.results || !desk.candidates || !desk.analysis)
        return EXIT_FAILURE;
    char *line;
    while ((line = read_line(jobs))) {
        if (*line && *line != '#')
            run_job(&desk, line);
        free(line);
    }
    fclose(jobs);
    int successes = 0;
    for (int i = 0; i < COMMAND_COUNT; ++i) {
        fprintf(desk.results, "TOTAL %s ok=%d errors=%d\n", command_names[i], desk.ok[i], desk.errors[i]);
        successes += desk.ok[i];
    }
    fprintf(desk.results, "SUMMARY jobs=%d ok=%d errors=%d messages=%d\n",
            desk.jobs, successes, desk.jobs - successes, desk.message_count);
    int failed = ferror(desk.results) || ferror(desk.candidates) || ferror(desk.analysis);
    if (fclose(desk.results) != 0)
        failed = 1;
    if (fclose(desk.candidates) != 0)
        failed = 1;
    if (fclose(desk.analysis) != 0)
        failed = 1;
    for (int i = 0; i < desk.message_count; ++i)
        free(desk.messages[i].body);
    free(desk.messages);
    return failed ? EXIT_FAILURE : EXIT_SUCCESS;
}
