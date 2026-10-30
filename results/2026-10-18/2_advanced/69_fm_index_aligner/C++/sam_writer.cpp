#include "aligner.hpp"
std::string ratio(I numerator, I denominator) {
    if (!denominator)
        return "-";
    I scaled = (10000 * numerator + denominator / 2) / denominator;
    std::ostringstream out;
    out << scaled / 10000 << '.' << std::setfill('0') << std::setw(4) << scaled % 10000;
    return out.str();
}
Lines sam_header(const std::vector<Reference> &references) {
    Lines out = {"@HD\tVN:1.6\tSO:unsorted"};
    for (const Reference &reference : references)
        line(out, "@SQ\tSN:", reference.name, "\tLN:", reference.bases.size());
    out.push_back("@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0");
    return out;
}
std::string sam_record(const Result &result, const std::vector<Reference> &references,
                       int maximum_alternatives) {
    std::ostringstream out;
    const Read &read = result.read;
    if (!result.mapped) {
        out << read.name << "\t4\t*\t0\t0\t*\t*\t0\t0\t" << read.bases << '\t' << read.quality
            << "\tYM:Z:" << result.reason;
        return out.str();
    }
    const Alignment &a = result.primary;
    std::string quality = read.quality;
    if (a.strand)
        std::reverse(quality.begin(), quality.end());
    out << read.name << '\t' << (a.strand ? 16 : 0) << '\t' << references[a.reference].name << '\t'
        << a.position + 1 << '\t' << result.mapq << '\t' << a.cigar << "\t*\t0\t0\t"
        << (a.strand ? reverse_complement(read.bases) : read.bases) << '\t' << quality
        << "\tNM:i:" << a.nm << "\tMD:Z:" << a.md << "\tAS:i:" << result.score
        << "\tX0:i:" << result.x0 << "\tX1:i:" << result.x1 << "\tYM:Z:" << result.method;
    if (result.other_count >= 1 && result.other_count <= maximum_alternatives) {
        out << "\tXA:Z:";
        for (const Alignment &other : result.others)
            out << references[other.reference].name << ',' << (other.strand ? '-' : '+')
                << other.position + 1 << ',' << other.cigar << ',' << other.nm << ';';
    }
    return out.str();
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name);
    for (const std::string &line : lines)
        out << line << '\n';
}
