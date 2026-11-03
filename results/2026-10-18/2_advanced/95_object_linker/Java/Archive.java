import java.util.*;
import java.util.function.*;
final class Archive {
    static final class Member {
        ObjectParser.Obj object;
        List<String> exports;
        boolean loaded;
        Member(ObjectParser.Obj object, List<String> exports) {
            this.object = object;
            this.exports = exports;
        }
    }
    static List<Member> read(String path) throws Exception {
        List<String> lines = ObjectParser.readLines(path);
        List<Member> members = new ArrayList<>();
        int index = 0;
        while (index < lines.size()) {
            List<String> header = List.of(lines.get(index).split(" "));
            ObjectParser.Parsed parsed =
                ObjectParser.parse(lines, index + 1, path + "(" + header.get(1) + ")");
            members.add(new Member(parsed.object(), header.subList(2, header.size())));
            index = parsed.next();
        }
        return members;
    }
    static int scan(List<Member> members, Predicate<String> undefined,
                    BiConsumer<ObjectParser.Obj, String> extract) {
        int extracted = 0;
        while (true) {
            boolean changed = false;
            for (Member member : members) {
                if (member.loaded)
                    continue;
                String reason = null;
                for (String name : member.exports)
                    if (undefined.test(name)) {
                        reason = name;
                        break;
                    }
                if (reason == null)
                    continue;
                member.loaded = true;
                extract.accept(member.object, reason);
                extracted++;
                changed = true;
            }
            if (!changed)
                return extracted;
        }
    }
}
