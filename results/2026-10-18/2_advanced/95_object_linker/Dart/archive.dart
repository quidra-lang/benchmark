part of 'main.dart';

class ArchiveMember {
  ObjectFile object;
  final List<String> exports;
  bool loaded = false;
  ArchiveMember(this.object, this.exports);
}

class Archive {
  final String name;
  final List<ArchiveMember> members = [];
  Archive(this.name);
}

class Extraction {
  final String object, reason, referrer;
  Extraction(this.object, this.reason, this.referrer);
}

Archive readArchive(String name) {
  final archive = Archive(name);
  ArchiveMember? member;
  var body = <String>[];
  for (final line in readLines('input/$name')) {
    final a = line.split(' ');
    if (a[0] == 'member') {
      member = ArchiveMember(ObjectFile('$name(${a[1]})'), a.skip(2).toList());
      body = [];
    } else {
      body.add(line);
      if (line == 'end') {
        final current = member!;
        current.object = parseObject(body, current.object.name);
        archive.members.add(current);
      }
    }
  }
  return archive;
}

int scanArchive(
  Archive archive,
  bool Function(String) undefined,
  String Function(String) referrer,
  void Function(ObjectFile) load,
  void Function(Extraction) record,
) {
  var total = 0;
  while (true) {
    var extracted = 0;
    for (final member in archive.members) {
      if (member.loaded) continue;
      String? reason;
      for (final name in member.exports) {
        if (undefined(name)) {
          reason = name;
          break;
        }
      }
      if (reason == null) continue;
      record(Extraction(member.object.name, reason, referrer(reason)));
      member.loaded = true;
      load(member.object);
      extracted++;
      total++;
    }
    if (extracted == 0) return total;
  }
}
