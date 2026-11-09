part of 'main.dart';

String pathText(List<int> path) => path.join(',');
String attributeText(Attribute a) =>
    'path ${pathText(a.path)} origin ${a.origin} med ${a.med} comm ${communitiesText(a.communities)}';
String routeText(Route? r) {
  if (r == null) return 'NONE';
  final a = r.attribute;
  return r.local
      ? 'LOCAL origin ${a.origin} comm ${communitiesText(a.communities)}'
      : 'next ${a.path.first} path ${pathText(a.path)} link ${r.link!.name} lp ${r.lp} med ${a.med} origin ${a.origin} comm ${communitiesText(a.communities)}';
}

void writeLines(String name, List<String> a) => File(
  'output/$name',
).writeAsStringSync(a.isEmpty ? '' : '${a.join('\n')}\n');
