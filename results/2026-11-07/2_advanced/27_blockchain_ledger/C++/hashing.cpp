#include "ledger.hpp"
std::string digest(const std::string &text) {
    const Integer bases[] = {1000003, 1500007, 2750159, 4194301};
    const Integer initials[] = {11, 23, 37, 53};
    std::ostringstream result;
    result << std::hex << std::setfill('0');
    for (int lane = 0; lane < 4; ++lane) {
        Integer value = initials[lane];
        for (unsigned char c : text)
            value = (value * bases[lane] + c) % 2147483647;
        for (Integer c : {Integer(text.size()), Integer(0), Integer(0)})
            value = (value * bases[lane] + c) % 2147483647;
        result << std::setw(8) << value;
    }
    return result.str();
}
std::string merkle(std::vector<std::string> ids) {
    while (ids.size() > 1) {
        if (ids.size() % 2)
            ids.push_back(ids.back());
        std::vector<std::string> next;
        for (std::size_t i = 0; i < ids.size(); i += 2)
            next.push_back(digest(ids[i] + ids[i + 1]));
        ids = std::move(next);
    }
    return ids.front();
}
std::string short_hash(const std::string &value) {
    return value.substr(0, 8);
}
