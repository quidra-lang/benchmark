#include "aligner.hpp"
Input read_inputs() {
    Input out;
    std::ifstream reference("input/reference.fasta");
    std::string value;
    while (std::getline(reference, value)) {
        if (value[0] == '>') {
            std::size_t end = value.find(' ');
            out.references.push_back(
                {value.substr(1, end == std::string::npos ? end : end - 1), "", 0});
        } else
            for (char character : value) {
                if (character >= 'a' && character <= 'z') {
                    ++out.references.back().masked;
                    character = char(character - 'a' + 'A');
                }
                out.references.back().bases += character;
            }
    }
    std::ifstream reads("input/reads.fastq");
    while (std::getline(reads, value)) {
        Read read;
        read.name = value.substr(1);
        std::getline(reads, read.bases);
        std::getline(reads, value);
        std::getline(reads, read.quality);
        out.reads.push_back(read);
    }
    std::ifstream parameters("input/params.txt");
    while (std::getline(parameters, value)) {
        std::istringstream row(value);
        std::string key;
        int number;
        row >> key;
        while (row >> number)
            out.parameters[key].push_back(number);
    }
    return out;
}
std::string reverse_complement(const std::string &sequence) {
    std::string out;
    for (auto at = sequence.rbegin(); at != sequence.rend(); ++at) {
        switch (*at) {
        case 'A':
            out += 'T';
            break;
        case 'C':
            out += 'G';
            break;
        case 'G':
            out += 'C';
            break;
        case 'T':
            out += 'A';
            break;
        default:
            out += 'N';
        }
    }
    return out;
}
