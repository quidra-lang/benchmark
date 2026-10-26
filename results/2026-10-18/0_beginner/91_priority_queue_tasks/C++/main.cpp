#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <queue>
#include <sstream>

struct Task {
    std::string name;
    int priority, order;
};

struct Later {
    bool operator()(const Task &a, const Task &b) const {
        return a.priority != b.priority ? a.priority > b.priority : a.order > b.order;
    }
};

int main() {
    std::priority_queue<Task, std::vector<Task>, Later> queue;
    int sequence = 0;
    const std::array<std::string, 16> operations = {"add email 3", "add backup 5", "add deploy 1", "run",
        "add report 3", "add test 2", "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run",
        "add build 1", "add docs 4", "run", "run"};
    for (const std::string &operation : operations) {
        if (operation == "run") {
            Task task = queue.top();
            queue.pop();
            std::cout << "run: " << task.name << " (priority " << task.priority << ")\n";
        } else {
            std::istringstream input(operation);
            std::string op;
            Task task;
            input >> op >> task.name >> task.priority;
            task.order = sequence++;
            queue.push(task);
        }
    }
    std::cout << "remaining:";
    while (!queue.empty()) {
        std::cout << ' ' << queue.top().name;
        queue.pop();
    }
    std::cout << '\n';
}
