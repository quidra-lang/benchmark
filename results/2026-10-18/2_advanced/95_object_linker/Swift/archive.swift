final class Member {
    let object: Object, exports: [String];
    var loaded = false;
    init(_ object: Object, _ exports: [String]) {
        self.object = object;
        self.exports = exports
    }
}
final class Archive {
    let members: [Member]
    init(_ name: String) {
        let lines = ObjectParser.lines(name);
        var members: [Member] = [], i = 0
        while i < lines.count {
            let fields = lines[i].split(separator: " ").map(String.init);
            i += 1;
            let start = i;
            while lines[i] != "end" {
                i += 1
            };
            i += 1;
            members.append(Member(ObjectParser.parse("\(name)(\(fields[1]))", Array(lines[start..<i])), Array(fields.dropFirst(2))))
        };
        self.members = members
    }
    func scan(_ extract: (Member) -> Bool) -> Bool {
        var any = false
        while true {
            var changed = false;
            for member in members where !member.loaded {
                if extract(member) {
                    member.loaded = true;
                    changed = true;
                    any = true
                }
            };
            if !changed {
                return any
            }
        }
    }
}
