#include "linker.h"
Archive *read_archive(const char *name) {
    Archive *archive = ml_alloc(sizeof(*archive));
    archive->name = name;
    StringList lines = read_lines(ml_format("input/%s", name)), body = {0};
    StringList exports = {0};
    const char *object_name = NULL;
    for (int i = 0; i < lines.count; ++i) {
        StringList a = words(lines.items[i]);
        if (equal(a.items[0], "member")) {
            object_name = ml_format("%s(%s)", name, a.items[1]);
            exports = (StringList){0};
            for (int j = 2; j < a.count; ++j)
                PUSH(exports, a.items[j]);
            body = (StringList){0};
        } else {
            PUSH(body, lines.items[i]);
            if (equal(lines.items[i], "end")) {
                ArchiveMember *member = ml_alloc(sizeof(*member));
                member->object = parse_object(body, object_name);
                member->exports = exports;
                PUSH(archive->members, member);
            }
        }
    }
    return archive;
}
int scan_archive(Archive *archive, Linker *linker) {
    int total = 0;
    while (true) {
        int extracted = 0;
        for (int i = 0; i < archive->members.count; ++i) {
            ArchiveMember *member = archive->members.items[i];
            if (member->loaded)
                continue;
            const char *reason = NULL;
            for (int j = 0; j < member->exports.count; ++j)
                if (undefined_name(linker, member->exports.items[j])) {
                    reason = member->exports.items[j];
                    break;
                }
            if (!reason)
                continue;
            Extraction record = {member->object->name, reason, referrer(linker, reason)};
            PUSH(linker->extractions, record);
            member->loaded = true;
            load_object(linker, member->object);
            ++extracted;
            ++total;
        }
        if (!extracted)
            return total;
    }
}
