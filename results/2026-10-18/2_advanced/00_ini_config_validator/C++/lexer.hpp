#pragma once

#include <optional>
#include <string>
#include <vector>

constexpr char LITERAL_DOLLAR = '\x01';

struct LexError {
    std::string code;
    std::string message;
};

struct LogicalLine {
    int number = 0;
    std::vector<std::string> segments;
    std::optional<LexError> error;

    void fail(const std::string& code, const std::string& message);
};

std::vector<std::string> read_lines(const std::string& path);
std::string trim_left(const std::string& text);
std::string trim_right(const std::string& text);
std::string trim(const std::string& text);
std::vector<std::string> split(const std::string& text, char separator);
std::string join(const std::vector<std::string>& parts, const std::string& separator);
std::vector<LogicalLine> logical_lines(const std::vector<std::string>& physical_lines);
