#include "scheduler.hpp"
Schedule decode(const Instance &data, const Chromosome &genes) {
    std::vector<int> next(14), ready(14), free(data.machines), starts(data.operations.size());
    for (int number : genes)
        for (const Job &job : data.jobs)
            if (job.number == number) {
                const int id = job.operations[next[number]++];
                const Operation &op = data.operations[id];
                starts[id] = std::max(ready[number], free[op.machine]);
                ready[number] = free[op.machine] = starts[id] + op.duration;
                break;
            }
    return from_starts(data, starts);
}
int tournament(Minstd &random, const std::vector<int> &values, int size) {
    int best = -1;
    for (int i = 0; i < size; ++i) {
        const int index = random.below(int(values.size()));
        if (best < 0 || std::tie(values[index], index) < std::tie(values[best], best))
            best = index;
    }
    return best;
}
std::pair<Chromosome, Chromosome> crossover(Minstd &random, const Instance &data, const Chromosome &a,
                                            const Chromosome &b) {
    std::set<int> selected;
    for (const Job &job : data.jobs)
        if (random.below(2) == 0)
            selected.insert(job.number);
    auto child = [&](const Chromosome &first, const Chromosome &second) {
        Chromosome result(first.size(), 0);
        std::size_t next = 0;
        for (std::size_t i = 0; i < first.size(); ++i)
            if (selected.count(first[i]))
                result[i] = first[i];
        for (int gene : second)
            if (!selected.count(gene)) {
                while (result[next])
                    ++next;
                result[next++] = gene;
            }
        return result;
    };
    return {child(a, b), child(b, a)};
}
void swap_mutation(Minstd &random, Chromosome &genes) {
    const int a = random.below(int(genes.size())), b = random.below(int(genes.size()));
    std::swap(genes[a], genes[b]);
}
void insertion_mutation(Minstd &random, Chromosome &genes) {
    const int a = random.below(int(genes.size())), b = random.below(int(genes.size())), value = genes[a];
    genes.erase(genes.begin() + a);
    genes.insert(genes.begin() + b, value);
}
