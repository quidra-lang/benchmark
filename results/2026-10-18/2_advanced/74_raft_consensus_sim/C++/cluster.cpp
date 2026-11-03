#include "raft.hpp"
std::string status_name(RequestStatus status) {
    return status == RequestStatus::Committed     ? "COMMITTED"
           : status == RequestStatus::Uncommitted ? "UNCOMMITTED"
           : status == RequestStatus::Lost        ? "LOST"
           : status == RequestStatus::Failed      ? "FAILED"
                                                  : "WAITING";
}
Input read_cluster() {
    Input out;
    std::ifstream cluster("input/cluster.txt");
    std::string text, key;
    std::map<std::string, std::vector<int>> values;
    while (std::getline(cluster, text)) {
        std::istringstream row(text);
        row >> key;
        int value;
        while (row >> value)
            values[key].push_back(value);
    }
    out.settings = {values["NODES"][0],     values["ELECTION"][0], values["ELECTION"][1],
                    values["HEARTBEAT"][0], values["BATCH"][0],    values["QUORUM"][0],
                    values["SEED"][0],      values["END"][0],      values["RETRY"][0],
                    values["ATTEMPTS"][0],  values["SAMPLE"][0]};
    std::ifstream script("input/script.txt");
    while (std::getline(script, text)) {
        std::istringstream row(text);
        int time;
        std::string kind;
        row >> time >> kind;
        if (kind == "REQUEST") {
            int destination;
            std::string operation;
            Command command;
            row >> destination >> operation >> command.key;
            command.kind = operation == "SET"   ? Operation::Set
                           : operation == "ADD" ? Operation::Add
                           : operation == "DEL" ? Operation::Delete
                                                : Operation::Get;
            if (command.kind == Operation::Set || command.kind == Operation::Add)
                row >> command.value;
            out.requests.push_back(
                {int(out.requests.size()) + 1, time, destination, command, time, destination});
        } else {
            Control control{time, kind == "CRASH"       ? ControlKind::Crash
                                  : kind == "RESTART"   ? ControlKind::Restart
                                  : kind == "PARTITION" ? ControlKind::Partition
                                  : kind == "HEAL"      ? ControlKind::Heal
                                                        : ControlKind::Transfer};
            if (control.kind == ControlKind::Partition) {
                std::string group;
                while (row >> group) {
                    std::istringstream members(group);
                    std::string node;
                    std::vector<int> nodes;
                    while (std::getline(members, node, ','))
                        nodes.push_back(std::stoi(node));
                    control.groups.push_back(nodes);
                }
            } else if (control.kind != ControlKind::Heal) {
                row >> control.first;
                if (control.kind == ControlKind::Transfer)
                    row >> control.second;
            }
            out.controls.push_back(control);
        }
    }
    return out;
}
