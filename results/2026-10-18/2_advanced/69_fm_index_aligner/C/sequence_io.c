#include "aligner.h"
Input *read_inputs(void) {
    Input *out = calloc(1, sizeof(Input));
    FILE *in = fopen("input/reference.fasta", "r");
    char *value;
    Text sequence = {0};
    while ((value = read_line(in))) {
        if (value[0] == '>') {
            if (out->reference_count) {
                Reference *old = &out->references[out->reference_count - 1];
                old->bases = sequence.data;
                old->length = (int)sequence.length;
            }
            sequence = (Text){0};
            Reference *reference = &out->references[out->reference_count++];
            int n = 0;
            while (value[n + 1] && value[n + 1] != ' ') {
                reference->name[n] = value[n + 1];
                ++n;
            }
            reference->name[n] = 0;
        } else
            for (int i = 0; value[i]; ++i) {
                char character = value[i];
                if (character >= 'a' && character <= 'z') {
                    ++out->references[out->reference_count - 1].masked;
                    character = (char)(character - 'a' + 'A');
                }
                text(&sequence, "%c", character);
            }
        free(value);
    }
    Reference *last = &out->references[out->reference_count - 1];
    last->bases = sequence.data;
    last->length = (int)sequence.length;
    fclose(in);
    in = fopen("input/reads.fastq", "r");
    while ((value = read_line(in))) {
        Read *read = &out->reads[out->read_count++];
        strcpy(read->name, value + 1);
        free(value);
        read->bases = read_line(in);
        read->length = (int)strlen(read->bases);
        value = read_line(in);
        free(value);
        read->quality = read_line(in);
    }
    fclose(in);
    in = fopen("input/params.txt", "r");
    for (int i = 0; i < 16; ++i) {
        value = read_line(in);
        strtok(value, " ");
        char *token;
        int j = 0;
        while ((token = strtok(NULL, " ")))
            out->parameters[i][j++] = atoi(token);
        free(value);
    }
    fclose(in);
    return out;
}
char *reverse_complement(const char *sequence) {
    int length = (int)strlen(sequence);
    char *out = malloc((size_t)length + 1);
    for (int i = 0; i < length; ++i) {
        switch (sequence[length - i - 1]) {
        case 'A':
            out[i] = 'T';
            break;
        case 'C':
            out[i] = 'G';
            break;
        case 'G':
            out[i] = 'C';
            break;
        case 'T':
            out[i] = 'A';
            break;
        default:
            out[i] = 'N';
        }
    }
    out[length] = 0;
    return out;
}
