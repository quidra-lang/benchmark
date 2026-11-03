part of 'main.dart';

double buckling(Member member, Section section, Material material) =>
    3.141592653589793 *
    3.141592653589793 *
    material.e *
    section.inertia /
    (member.length * member.length);
double utilization(
  double force,
  Member member,
  Section section,
  Material material,
) => max(
  (force / section.area).abs() / material.fy,
  max(0.0, -force) / buckling(member, section, material),
);
double slenderness(Member member, Section section) =>
    member.length / sqrt(section.inertia / section.area);
double slendernessLimit(int member, List<Result> combinations, Model m) {
  for (final r in combinations) {
    if (r.forces[member] < 0) return m.settings.compression;
  }
  return m.settings.tension;
}

int selectSection(int group, List<Result> combinations, Model m) {
  for (var section = 0; section < m.sections.length; section++) {
    final candidate = m.sections[section];
    var valid = true;
    for (var i = 0; i < m.members.length; i++) {
      final member = m.members[i];
      if (member.group != group) continue;
      if (slenderness(member, candidate) >
          slendernessLimit(i, combinations, m)) {
        valid = false;
        break;
      }
      for (final r in combinations) {
        if (utilization(
              r.forces[i],
              member,
              candidate,
              m.materials[member.material],
            ) >
            1) {
          valid = false;
          break;
        }
      }
      if (!valid) break;
    }
    if (valid) return section;
  }
  return m.sections.length - 1;
}
