'use strict';

const fs = require('node:fs');
const { prefixValue, contains } = require('./topology');
const NO_EXPORT = 65535 * 65536 + 65281;

function communityValue(text) {
  if (text === 'NO_EXPORT') return NO_EXPORT;
  const [high, low] = text.split(':').map(Number);
  return high * 65536 + low;
}

const communityText = value => value === NO_EXPORT ? 'NO_EXPORT' : Math.floor(value / 65536) + ':' + value % 65536;
const parseCommunities = values => Array.from(new Set(values.map(communityValue))).sort((a, b) => a - b);
const communitiesText = values => values.length ? values.map(communityText).join(',') : '-';

function editCommunities(values, rule) {
  const result = new Set(values);
  if (rule) for (const action of rule.actions) {
    if (action.kind === 'ADD') result.add(action.value);
    else if (action.kind === 'REMOVE') result.delete(action.value);
  }
  return Array.from(result).sort((a, b) => a - b);
}

function readPolicies(path) {
  const lists = new Map(), rules = [], byName = new Map();
  for (const line of fs.readFileSync(path, 'ascii').split('\n').slice(0, -1)) {
    const fields = line.split(' ');
    if (fields[0] === 'PLIST') {
      const [, name, action, text] = fields, prefix = prefixValue(text);
      let ge = null, le = null;
      for (let i = 4; i < fields.length; i += 2) {
        if (fields[i] === 'GE') ge = Number(fields[i + 1]);
        else le = Number(fields[i + 1]);
      }
      if (!lists.has(name)) lists.set(name, []);
      lists.get(name).push({ action, prefix, low: ge === null ? prefix.length : ge,
        high: le === null ? ge === null ? prefix.length : 32 : le });
    } else {
      const [, name, state, asn, direction, target] = fields;
      const rule = { name, active: state === 'ON', asn: Number(asn), direction, target, conditions: [], actions: [], hits: 0 };
      let i = 6;
      while (fields[i] !== 'THEN') {
        const kind = fields[i++], text = fields[i++];
        const value = kind === 'PREFIX' ? text : kind === 'LENGTH' ? text.split('-').map(Number) :
          kind === 'COMMUNITY' ? communityValue(text) : Number(text);
        rule.conditions.push({ kind, value });
      }
      for (i++; i < fields.length;) {
        const kind = fields[i++];
        const value = kind === 'DENY' || kind === 'ALLOW' ? true :
          kind === 'ADD' || kind === 'REMOVE' ? communityValue(fields[i++]) : Number(fields[i++]);
        rule.actions.push({ kind, value });
        if (kind !== 'ADD' && kind !== 'REMOVE') rule[kind] = value;
      }
      rules.push(rule); byName.set(name, rule);
    }
  }
  return { lists, rules, byName };
}

function permitted(entries, text) {
  const prefix = prefixValue(text);
  for (const entry of entries) {
    if (entry.low <= prefix.length && prefix.length <= entry.high && contains(entry.prefix, prefix.value)) return entry.action === 'PERMIT';
  }
  return false;
}

function appliedRule(policies, direction, session, prefix, path, communities) {
  for (const rule of policies.rules) {
    if (!rule.active || rule.direction !== direction || rule.asn !== session.owner.asn) continue;
    if (rule.target !== '*' && rule.target !== String(session.neighbor) && rule.target !== session.link.name) continue;
    const matches = rule.conditions.every(({ kind, value }) => {
      if (kind === 'PREFIX') return permitted(policies.lists.get(value), prefix);
      if (kind === 'CONTAINS') return path.includes(value);
      if (kind === 'ORIGINAS') return (path.length ? path[path.length - 1] : session.owner.asn) === value;
      if (kind === 'LENGTH') return value[0] <= path.length && path.length <= value[1];
      return communities.includes(value);
    });
    if (matches) return rule;
  }
  return null;
}

module.exports = { NO_EXPORT, communityValue, parseCommunities, communitiesText, editCommunities, readPolicies, permitted, appliedRule };
