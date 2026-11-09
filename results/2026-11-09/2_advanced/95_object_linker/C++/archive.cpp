#include "linker.hpp"
std::unique_ptr<Archive> read_archive(const std::string &name) {
    auto archive = std::make_unique<Archive>();
    archive->name = name;
    std::string object_name;
    std::vector<std::string> exports, body;
    for (const std::string &line : read_lines("input/" + name)) {
        std::vector<std::string> a = words(line);
        if (a[0] == "member") {
            object_name = name + "(" + a[1] + ")";
            exports.assign(a.begin() + 2, a.end());
            body.clear();
        } else {
            body.push_back(line);
            if (line == "end") {
                ArchiveMember member;
                member.object = parse_object(body, object_name);
                member.exports = exports;
                archive->members.push_back(std::move(member));
            }
        }
    }
    return archive;
}
int scan_archive(Archive &archive, const std::function<bool(const std::string &)> &undefined,
                 const std::function<std::string(const std::string &)> &referrer,
                 const std::function<void(Object *)> &load,
                 const std::function<void(Extraction)> &record) {
    int total = 0;
    while (true) {
        int extracted = 0;
        for (ArchiveMember &member : archive.members) {
            if (member.loaded)
                continue;
            std::string reason;
            for (const std::string &name : member.exports)
                if (undefined(name)) {
                    reason = name;
                    break;
                }
            if (reason.empty())
                continue;
            record({member.object->name, reason, referrer(reason)});
            member.loaded = true;
            load(member.object.get());
            ++extracted;
            ++total;
        }
        if (!extracted)
            return total;
    }
}
