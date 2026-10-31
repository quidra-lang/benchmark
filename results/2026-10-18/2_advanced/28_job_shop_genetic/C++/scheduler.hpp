#pragma once
#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Chromosome = std::vector<int>;
using Order = std::vector<std::vector<int>>;
struct Operation {
    int job, index, machine, duration, head, tail, previous = -1, next = -1;
};
struct Job {
    int number, work;
    std::vector<int> operations;
};
struct Machine {
    int count = 0, load = 0, head = 1000000, tail = 1000000, bound = 0;
};
struct Instance {
    int machines;
    std::vector<Operation> operations;
    std::vector<Job> jobs;
    std::vector<Machine> machine;
    std::vector<std::string> errors;
    int work = 0;
};
Instance read_instance();
std::string notation(const Operation &);
class Minstd {
    Integer state;

  public:
    explicit Minstd(Integer seed) : state(seed) {
    }
    Integer draw();
    int below(int);
    bool chance(std::pair<int, int>);
    void shuffle(Chromosome &);
};
struct Schedule {
    std::vector<int> start, finish, previous, next;
    Order order;
    int makespan = 0, decisions = 0, ties = 0;
};
Schedule schedule_order(const Instance &, const Order &, int inflated = -1);
Schedule from_starts(const Instance &, const std::vector<int> &);
Chromosome chromosome(const Instance &, const Schedule &);
Schedule dispatch(const Instance &, const std::string &, const Chromosome &genes = {});
Schedule decode(const Instance &, const Chromosome &);
int tournament(Minstd &, const std::vector<int> &, int);
std::pair<Chromosome, Chromosome> crossover(Minstd &, const Instance &, const Chromosome &,
                                            const Chromosome &);
void swap_mutation(Minstd &, Chromosome &);
void insertion_mutation(Minstd &, Chromosome &);
struct Chart {
    int scale, columns;
    std::vector<std::string> lines;
};
Chart gantt(const Instance &, const Schedule &, const std::vector<int> &, int);
