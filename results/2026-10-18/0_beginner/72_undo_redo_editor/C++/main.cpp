#include <iostream>
#include <string>
#include <vector>
#include <array>

int main() {
    std::array<std::string, 14> commands = {"undo", "type hello world", "delete 5", "type there",
        "undo", "undo", "redo", "type friend", "redo", "delete 20", "undo", "redo", "redo", "type see you"};
    std::string buffer;
    std::vector<std::string> undo, redo;
    for (const std::string &command : commands) {
        if (command == "undo") {
            if (undo.empty()) {
                std::cout << "undo => nothing to undo\n";
                continue;
            }
            redo.push_back(buffer);
            buffer = undo.back();
            undo.pop_back();
        } else if (command == "redo") {
            if (redo.empty()) {
                std::cout << "redo => nothing to redo\n";
                continue;
            }
            undo.push_back(buffer);
            buffer = redo.back();
            redo.pop_back();
        } else {
            undo.push_back(buffer);
            redo.clear();
            if (command.compare(0, 5, "type ") == 0) {
                buffer += command.substr(5);
            } else {
                std::size_t count = static_cast<std::size_t>(std::stoi(command.substr(7)));
                buffer.resize(count > buffer.size() ? 0 : buffer.size() - count);
            }
        }
        std::cout << command << " => \"" << buffer << "\"\n";
    }
}
