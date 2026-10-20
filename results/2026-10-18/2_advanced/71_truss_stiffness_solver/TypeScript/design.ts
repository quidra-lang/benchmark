import type { Properties } from './assembly.ts';
import type { Section } from './model_io.ts';

export const pi = 3.141592653589793;
export const buckling = (member: Properties, inertia = member.inertia) =>
  (pi * pi * member.material.young * inertia) / (member.length * member.length);
export function utilization(
  force: number,
  member: Properties,
  area = member.area,
  inertia = member.inertia,
): number {
  return Math.max(
    Math.abs(force / area) / member.material.yield,
    Math.max(0, -force) / buckling(member, inertia),
  );
}
export const slenderness = (member: Properties, area = member.area, inertia = member.inertia) =>
  member.length / Math.sqrt(inertia / area);
export const slendernessLimit = (forces: number[], compression: number, tension: number) =>
  forces.some((force) => force < 0) ? compression : tension;
export function selectSection(
  group: number[],
  catalogue: Section[],
  properties: Properties[],
  forces: number[][],
  limits: number[],
): number {
  const selected = catalogue.findIndex((section) =>
    group.every(
      (m) =>
        slenderness(properties[m], section.area, section.inertia) <= limits[m] &&
        forces.every(
          (result) => utilization(result[m], properties[m], section.area, section.inertia) <= 1,
        ),
    ),
  );
  return selected < 0 ? catalogue.length - 1 : selected;
}
