import { readFileSync } from 'node:fs';
import type { RbacEngine, RbacRole, Permission, RoleConstraint, Assignment, Diagnostic } from './types.ts';

export const permissionKey = (action: string, type: string): string => action + '\0' + type;

export class Rbac implements RbacEngine {
  roles: Map<string,RbacRole>;
  permissions: Permission[];
  ssd: RoleConstraint[];
  dsd: RoleConstraint[];
  assignments: Assignment[];
  byUser: Map<string,Assignment[]>;
  diagnostics: Diagnostic[];
  cachedClosures: Map<string,Set<string>> | null;
  constructor(lines: string[]) {
    this.roles = new Map<string,RbacRole>();
    this.permissions = [];
    this.ssd = [];
    this.dsd = [];
    this.assignments = [];
    this.byUser = new Map<string,Assignment[]>();
    this.diagnostics = [];
    this.cachedClosures = null;
    const records = lines.map((line, index) => ({fields: line.split(' '), line: index + 1}));
    for (const keyword of ['ROLE', 'INHERITS', 'PERMIT', 'SSD', 'DSD', 'ASSIGN']) {
      for (const record of records) {
        if (record.fields[0] !== keyword) continue;
        const reason = this.accept(record.fields);
        if (reason !== null) this.diagnostics.push({line: record.line, keyword, reason});
      }
      if (keyword === 'INHERITS') {
        const closures = new Map<string,Set<string>>();
        for (const role of this.roles.keys()) closures.set(role, this.closure([role]));
        this.cachedClosures = closures;
      }
    }
    this.diagnostics.sort((a, b) => a.line - b.line);
  }

  closure(seeds: Iterable<string>): Set<string> {
    const found = new Set<string>();
    if (this.cachedClosures !== null) {
      for (const seed of seeds) for (const role of this.cachedClosures.get(seed)!) found.add(role);
      return found;
    }
    const pending = [...seeds];
    for (let index = 0; index < pending.length; index++) {
      const role = pending[index];
      if (found.has(role)) continue;
      found.add(role);
      for (const junior of this.roles.get(role)!.juniors) pending.push(junior);
    }
    return found;
  }

  path(start: string, target: string): string[] | null {
    const failed = new Set<string>();
    const visit = (role: string): string[] | null => {
      if (role === target) return [role];
      if (failed.has(role)) return null;
      for (const junior of [...this.roles.get(role).juniors].sort()) {
        const rest = visit(junior);
        if (rest !== null) return [role, ...rest];
      }
      failed.add(role);
      return null;
    };
    return visit(start);
  }

  assigned(user: string, day: number): Set<string> {
    const result = new Set<string>();
    for (const assignment of this.byUser.get(user) || []) {
      if (assignment.first <= day && day <= assignment.last) result.add(assignment.role);
    }
    return result;
  }

  authorized(user: string, day: number): Set<string> {
    return this.closure(this.assigned(user, day));
  }

  accept(fields: string[]): string | null {
    const [keyword, name] = fields;
    if (keyword === 'ROLE') {
      if (this.roles.has(name)) return `duplicate role ${name}`;
      this.roles.set(name, {juniors: new Set(), permissions: new Set()});
    } else if (keyword === 'INHERITS') {
      const junior = fields[2];
      for (const role of [name, junior]) if (!this.roles.has(role)) return `unknown role ${role}`;
      if (this.roles.get(name)!.juniors.has(junior)) return `duplicate inheritance ${name} ${junior}`;
      const path = this.path(junior, name);
      if (path !== null) return 'cycle ' + [name, ...path].join(' > ');
      this.roles.get(name).juniors.add(junior);
    } else if (keyword === 'PERMIT') {
      const [, role, action, type] = fields;
      if (!this.roles.has(role)) return `unknown role ${role}`;
      const key = permissionKey(action, type);
      if (this.roles.get(role)!.permissions.has(key)) return `duplicate permission ${role} ${action} ${type}`;
      this.roles.get(role).permissions.add(key);
      this.permissions.push({role, action, type});
    } else if (keyword === 'SSD' || keyword === 'DSD') {
      const constraints = keyword === 'SSD' ? this.ssd : this.dsd;
      if (constraints.some(constraint => constraint.name === name)) return `duplicate constraint ${name}`;
      const roles = fields[3].split(',');
      for (const role of roles) if (!this.roles.has(role)) return `unknown role ${role}`;
      const cardinality = Number(fields[2]);
      if (cardinality < 2 || cardinality > roles.length) return `bad cardinality ${name} ${cardinality}`;
      constraints.push({name, cardinality, roles});
    } else {
      const role = fields[2];
      if (!this.roles.has(role)) return `unknown role ${role}`;
      const first = Number(fields[3]);
      const last = Number(fields[4]);
      if (!(1 <= first && first <= last && last <= 365)) return `bad range ${first} ${last}`;
      for (const constraint of this.ssd) {
        for (let day = first; day <= last; day++) {
          const assigned = this.assigned(name, day);
          assigned.add(role);
          const authorized = this.closure(assigned);
          const overlap = constraint.roles.filter(item => authorized.has(item)).sort();
          if (overlap.length >= constraint.cardinality) return `ssd ${constraint.name} day ${day} roles ${overlap.join(',')}`;
        }
      }
      const assignment = {user: name, role, first, last};
      this.assignments.push(assignment);
      if (!this.byUser.has(name)) this.byUser.set(name, []);
      this.byUser.get(name)!.push(assignment);
    }
    return null;
  }
}

export function readRbac(): Rbac {
  const text = readFileSync('input/rbac.txt', 'ascii');
  return new Rbac(text === '' ? [] : text.slice(0, -1).split('\n'));
}

