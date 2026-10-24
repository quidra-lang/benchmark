#include <iostream>
#include <string>
#include <vector>
#include <array>

int main() {
    for (const std::string &s : std::array<std::string, 7>{"(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}",
        "f(a[i] + g(b)}", "(1 + 2)) * 3", "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}"}) {
        std::vector<char> stack;
        int error = -1;
        for (int i = 0; i < static_cast<int>(s.size()); i++) {
            char c = s[i];
            if (c == '(' || c == '[' || c == '{')
                stack.push_back(c);
            else if (c == ')' || c == ']' || c == '}') {
                char expected = c == ')' ? '(' : c == ']' ? '[' : '{';
                if (stack.empty() || stack.back() != expected) {
                    error = i;
                    break;
                }
                stack.pop_back();
            }
        }
        if (error < 0 && !stack.empty())
            error = static_cast<int>(s.size());
        std::cout << s << " -> ";
        if (error < 0)
            std::cout << "balanced\n";
        else
            std::cout << "error at index " << error << '\n';
    }
}
