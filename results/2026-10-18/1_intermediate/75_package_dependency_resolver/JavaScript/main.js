const fs = require("node:fs");

const numberPattern = /^(?:0|[1-9][0-9]{0,3})$/;
const registry = new Map();
const constraintCache = new Map();
let requests = [];
let installed = new Map();
const held = new Set();
const advisories = new Map();
const history = [];
const output = [];
function fail(message) {
    throw new Error("error: " + message);
}
function compareText(a, b) {
    return a < b ? -1 : a > b ? 1 : 0;
}
function version(text) {
    const match = /^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([a-z0-9]+(?:\.[a-z0-9]+)*))?$/.exec(text);
    if (match === null || !match.slice(1, 4).every((part) => numberPattern.test(part))) return null;
    const pre = match[4] === undefined ? [] : match[4].split(".");
    if (pre.some((part) => /^[0-9]+$/.test(part) && !numberPattern.test(part))) return null;
    return { text, core: match.slice(1, 4).map(Number), pre };
}
function requireVersion(text) {
    const result = version(text);
    if (result === null) fail(`invalid version '${text}'`);
    return result;
}
function compareVersions(a, b) {
    for (let i = 0; i < 3; i++) if (a.core[i] !== b.core[i]) return a.core[i] - b.core[i];
    if (!a.pre.length || !b.pre.length) return (b.pre.length ? 1 : 0) - (a.pre.length ? 1 : 0);
    for (let i = 0; i < Math.min(a.pre.length, b.pre.length); i++) {
        const x = a.pre[i],
            y = b.pre[i],
            nx = /^[0-9]+$/.test(x),
            ny = /^[0-9]+$/.test(y);
        const order =
            nx && ny ? Number(x) - Number(y) : nx !== ny ? (nx ? -1 : 1) : compareText(x, y);
        if (order !== 0) return order;
    }
    return a.pre.length - b.pre.length;
}
function synthetic(core, pre = []) {
    return { core, pre, text: core.join(".") + (pre.length ? "-" + pre.join(".") : "") };
}
function parseConstraint(text) {
    const alternatives = [];
    for (const alternative of text.split(" || ")) {
        const comparators = [],
            prereleases = new Set();
        for (const term of alternative.split(" ")) {
            if (!term) return null;
            const op =
                [">=", "<=", ">", "<", "=", "^", "~"].find((op) => term.startsWith(op)) ?? "";
            const pattern = term.slice(op.length),
                prerelease = version(pattern);
            let core = [0, 0, 0],
                count = 0,
                lower;
            if (prerelease !== null && prerelease.pre.length) {
                core = prerelease.core;
                count = 3;
                lower = prerelease;
                prereleases.add(core.join("."));
            } else {
                const parts = pattern.split(".");
                if (parts.length < 1 || parts.length > 3) return null;
                let wildcard = false;
                for (const part of parts) {
                    if (part === "x" || part === "*") wildcard = true;
                    else if (!wildcard && numberPattern.test(part)) core[count++] = Number(part);
                    else return null;
                }
                lower = synthetic(core);
            }
            const add = (operator, bound) => comparators.push({ op: operator, bound });
            const upper = (index) =>
                synthetic(
                    core.map((value, i) =>
                        i < index - 1 ? value : i === index - 1 ? value + 1 : 0,
                    ),
                );
            if (count === 0) {
                if (op === ">" || op === "<") add("<", synthetic([0, 0, 0], ["0"]));
            } else if (op === "" || op === "=") {
                if (count === 3) add("=", lower);
                else {
                    add(">=", lower);
                    add("<", upper(count));
                }
            } else if (op === ">")
                add(count === 3 ? ">" : ">=", count === 3 ? lower : upper(count));
            else if (op === "<=") add(count === 3 ? "<=" : "<", count === 3 ? lower : upper(count));
            else if (op === ">=" || op === "<") add(op, lower);
            else if (op === "~") {
                add(">=", lower);
                add("<", upper(count === 1 ? 1 : 2));
            } else if (op === "^") {
                add(">=", lower);
                add(
                    "<",
                    upper(core[0] !== 0 || count === 1 ? 1 : core[1] !== 0 || count === 2 ? 2 : 3),
                );
            } else return null;
        }
        alternatives.push({ comparators, prereleases });
    }
    return {
        alternatives,
        normal: alternatives
            .map(
                (alternative) =>
                    alternative.comparators
                        .map((comparator) => comparator.op + comparator.bound.text)
                        .join(" ") || "*",
            )
            .join(" || "),
    };
}
function constraint(text) {
    if (constraintCache.has(text)) return constraintCache.get(text);
    const result = parseConstraint(text);
    if (result === null) fail(`invalid constraint '${text}'`);
    constraintCache.set(text, result);
    return result;
}
function satisfies(value, range) {
    return range.alternatives.some(
        (alternative) =>
            (!value.pre.length || alternative.prereleases.has(value.core.join("."))) &&
            alternative.comparators.every((comparator) => {
                const order = compareVersions(value, comparator.bound);
                return comparator.op === "="
                    ? order === 0
                    : comparator.op === ">"
                      ? order > 0
                      : comparator.op === ">="
                        ? order >= 0
                        : comparator.op === "<"
                          ? order < 0
                          : order <= 0;
            }),
    );
}
function versions(name) {
    return [...(registry.get(name)?.values() ?? [])].sort((a, b) =>
        compareVersions(b.version, a.version),
    );
}
function registered(name, text) {
    const result = registry.get(name)?.get(text);
    if (result === undefined) fail(`${name}@${text} is not registered`);
    return result;
}
function packageText(item) {
    return item.name + "@" + item.version.text;
}
function applicable(item) {
    return [...advisories.keys()].sort().filter((id) => {
        const advisory = advisories.get(id);
        return advisory.name === item.name && satisfies(item.version, advisory.range);
    });
}
function display(item) {
    const current = installed.get(item.name)?.version.text === item.version.text;
    return (
        packageText(item) +
        (item.yanked
            ? current
                ? " (yanked, installed)"
                : " (yanked)"
            : current
              ? " (installed)"
              : "")
    );
}
function requirementChain(requirement) {
    const result = [];
    for (let current = requirement; current !== null; current = current.parent)
        result.push(
            current.origin === null
                ? `requested ${current.name} ${current.raw}`
                : `${current.origin} requires ${current.name} ${current.raw}`,
        );
    return result.reverse();
}
function resolve(wanted, preferred, audit) {
    const selected = new Map();
    let failure = null;
    const usable = (item) =>
        (!item.yanked || installed.get(item.name)?.version.text === item.version.text) &&
        (!audit || !applicable(item).length);
    function record(requirement, reason, other = null) {
        if (failure === null || selected.size > failure.size)
            failure = {
                size: selected.size,
                chain: requirementChain(requirement),
                reason,
                other: other === null ? null : requirementChain(other),
            };
    }
    function search(requirements) {
        if (!requirements.length) return true;
        const [requirement, ...rest] = requirements,
            name = requirement.name;
        const existing = selected.get(name);
        if (existing !== undefined) {
            if (satisfies(existing.item.version, requirement.range)) return search(rest);
            record(
                requirement,
                `${packageText(existing.item)} was selected by:`,
                existing.requirement,
            );
            return false;
        }
        let candidates;
        if (held.has(name)) {
            const item = installed.get(name);
            if (!satisfies(item.version, requirement.range) || !usable(item)) {
                record(requirement, `${packageText(item)} is held`);
                return false;
            }
            candidates = [item];
        } else {
            candidates = versions(name).filter(
                (item) => satisfies(item.version, requirement.range) && usable(item),
            );
            if (preferred.has(name)) {
                const at = candidates.findIndex(
                    (item) => item.version.text === installed.get(name)?.version.text,
                );
                if (at >= 0) candidates.unshift(candidates.splice(at, 1)[0]);
            }
            if (!candidates.length) {
                record(requirement, `no version of ${name} matches ${requirement.raw}`);
                return false;
            }
        }
        for (const item of candidates) {
            let conflict = null;
            for (const otherName of [...selected.keys()].sort()) {
                const other = selected.get(otherName);
                if (
                    item.conflicts.some(
                        (dep) => dep.name === otherName && satisfies(other.item.version, dep.range),
                    ) ||
                    other.item.conflicts.some(
                        (dep) => dep.name === name && satisfies(item.version, dep.range),
                    )
                ) {
                    conflict = other;
                    break;
                }
            }
            if (conflict !== null) {
                record(
                    requirement,
                    `${packageText(item)} conflicts with ${packageText(conflict.item)}, which was selected by:`,
                    conflict.requirement,
                );
                continue;
            }
            selected.set(name, { item, requirement });
            const dependencies = item.deps.map((dep) => ({
                ...dep,
                origin: packageText(item),
                parent: requirement,
            }));
            if (search([...dependencies, ...rest])) return true;
            selected.delete(name);
        }
        return false;
    }
    const requirements = wanted.map((request) => ({ ...request, origin: null, parent: null }));
    if (search(requirements))
        return {
            installation: new Map([...selected].map(([name, entry]) => [name, entry.item])),
            failure: null,
        };
    return { installation: null, failure };
}
function reportFailure(failure) {
    output.push(
        "UNSATISFIABLE",
        ...failure.chain.map((line) => "  " + line),
        "  " + failure.reason,
    );
    if (failure.other !== null) output.push(...failure.other.map((line) => "    " + line));
}
function plan(next) {
    const remaining = new Set([...next.keys()].sort()),
        arranged = new Set(),
        counts = [0, 0, 0, 0],
        lines = [];
    while (remaining.size) {
        const name = [...remaining].find((name) =>
                next.get(name).deps.every((dep) => arranged.has(dep.name)),
            ),
            item = next.get(name),
            old = installed.get(name);
        if (old === undefined) {
            lines.push("install " + packageText(item));
            counts[0]++;
        } else if (old.version.text !== item.version.text) {
            const upgrading = compareVersions(item.version, old.version) > 0;
            lines.push(
                `${upgrading ? "upgrade" : "downgrade"} ${name} ${old.version.text} -> ${item.version.text}`,
            );
            counts[upgrading ? 1 : 2]++;
        }
        remaining.delete(name);
        arranged.add(name);
    }
    const removals = new Set([...installed.keys()].filter((name) => !next.has(name)).sort());
    while (removals.size) {
        const name = [...removals].find(
            (name) =>
                ![...removals].some((other) =>
                    installed.get(other).deps.some((dep) => dep.name === name),
                ),
        );
        lines.push("remove " + packageText(installed.get(name)));
        counts[3]++;
        removals.delete(name);
    }
    output.push(
        ...(lines.length
            ? [
                  ...lines,
                  `${counts[0]} installed, ${counts[1]} upgraded, ${counts[2]} downgraded, ${counts[3]} removed`,
              ]
            : ["no changes"]),
    );
}
function update(wanted, next, snapshot = true) {
    if (snapshot)
        history.push({
            requests: requests.map((request) => ({ ...request })),
            installed: new Map(installed),
        });
    requests = wanted.map((request) => ({ ...request }));
    installed = new Map(next);
    for (const name of held) if (!installed.has(name)) held.delete(name);
}
function reach(wanted) {
    const seen = new Set(wanted.map((request) => request.name)),
        queue = [...seen];
    for (let i = 0; i < queue.length; i++)
        for (const dep of installed.get(queue[i]).deps)
            if (!seen.has(dep.name)) {
                seen.add(dep.name);
                queue.push(dep.name);
            }
    return seen;
}
function requiredBy(name) {
    return [...installed.keys()]
        .sort()
        .find((other) => installed.get(other).deps.some((dep) => dep.name === name));
}
function cut(text) {
    const at = text.indexOf(" ");
    return at < 0 ? [text, null] : [text.slice(0, at), text.slice(at + 1)];
}
function execute(commandLine) {
    const [command, argument] = cut(commandLine),
        words = argument === null ? [] : argument.split(" ");
    const name = words[0];
    if (command === "PKG") {
        const parts = commandLine.split("; "),
            main = parts[0].split(" "),
            packageName = main[1],
            text = main[2],
            parsed = requireVersion(text);
        if (registry.get(packageName)?.has(text))
            fail(`${packageName}@${text} is already registered`);
        const deps = [],
            conflicts = [];
        for (const clause of parts.slice(1)) {
            const [kind, rest] = cut(clause),
                [other, raw] = cut(rest),
                range = constraint(raw);
            (kind === "DEP" ? deps : conflicts).push({ name: other, raw, range });
        }
        if (!registry.has(packageName)) registry.set(packageName, new Map());
        registry
            .get(packageName)
            .set(text, { name: packageName, version: parsed, deps, conflicts, yanked: false });
        output.push(`registered ${packageName}@${text}`);
        return;
    }
    if (command === "YANK" || command === "INFO") {
        const item = registered(name, words[1]);
        if (command === "YANK") {
            if (item.yanked) fail(packageText(item) + " is already yanked");
            item.yanked = true;
            output.push("yanked " + packageText(item));
        } else
            output.push(
                display(item),
                ...item.deps.map((dep) => `  requires ${dep.name} ${dep.raw}`),
                ...item.conflicts.map((dep) => `  conflicts with ${dep.name} ${dep.raw}`),
                ...applicable(item).map((id) => "  advisory " + id),
            );
        return;
    }
    if (command === "COMPARE") {
        const a = requireVersion(words[0]),
            b = requireVersion(words[1]),
            order = compareVersions(a, b);
        output.push(`${words[0]} ${order < 0 ? "<" : order > 0 ? ">" : "="} ${words[1]}`);
        return;
    }
    if (command === "MATCH") {
        const [text, raw] = cut(argument),
            parsed = requireVersion(text),
            range = constraint(raw);
        output.push(satisfies(parsed, range) ? "yes" : "no");
        return;
    }
    if (command === "RANGE") {
        output.push(constraint(argument).normal);
        return;
    }
    if (command === "VERSIONS" || command === "INSTALL" || command === "SIMULATE") {
        const [packageName, rest] = cut(argument),
            raw = rest ?? "*";
        const range = constraint(raw);
        if (!registry.has(packageName)) fail("unknown package " + packageName);
        if (command === "VERSIONS") {
            const selected = versions(packageName).filter(
                (item) => rest === null || satisfies(item.version, range),
            );
            output.push(...(selected.length ? selected.map(display) : ["no matching versions"]));
            return;
        }
        const wanted = requests.map((request) => ({ ...request })),
            at = wanted.findIndex((request) => request.name === packageName),
            request = { name: packageName, raw, range };
        if (at >= 0) wanted[at] = request;
        else wanted.push(request);
        const result = resolve(wanted, new Set(installed.keys()), false);
        if (result.installation === null) reportFailure(result.failure);
        else {
            plan(result.installation);
            if (command === "INSTALL") update(wanted, result.installation);
        }
        return;
    }
    if (command === "DEPENDENTS") {
        const parsed = words.length > 1 ? requireVersion(words[1]) : null,
            lines = [];
        for (const other of [...registry.keys()].sort())
            for (const item of versions(other))
                for (const dep of item.deps)
                    if (dep.name === name && (parsed === null || satisfies(parsed, dep.range)))
                        lines.push(`${packageText(item)} requires ${name} ${dep.raw}`);
        output.push(...(lines.length ? lines : ["no dependents"]));
        return;
    }
    if (command === "REMOVE") {
        const at = requests.findIndex((request) => request.name === name);
        if (at < 0)
            fail(
                installed.has(name)
                    ? `${name} is required by ${requiredBy(name)}`
                    : `${name} is not installed`,
            );
        const wanted = requests.filter((request) => request.name !== name),
            keep = reach(wanted);
        if (keep.has(name)) {
            output.push(
                `${packageText(installed.get(name))} is still required by ${requiredBy(name)}`,
            );
            update(wanted, installed);
        } else {
            const next = new Map([...installed].filter(([packageName]) => keep.has(packageName)));
            plan(next);
            update(wanted, next);
        }
        return;
    }
    if (command === "UPGRADE" || (command === "AUDIT" && argument === "FIX")) {
        if (command === "UPGRADE" && argument !== null && !installed.has(name))
            fail(`${name} is not installed`);
        const preferred =
            command === "AUDIT" || argument !== null
                ? new Set(
                      [...installed.keys()].filter(
                          (packageName) => command === "AUDIT" || packageName !== name,
                      ),
                  )
                : new Set();
        const result = resolve(requests, preferred, command === "AUDIT");
        if (result.installation === null) reportFailure(result.failure);
        else {
            plan(result.installation);
            update(requests, result.installation);
        }
        return;
    }
    if (command === "ROLLBACK") {
        if (!history.length) fail("nothing to roll back");
        const snapshot = history.pop();
        plan(snapshot.installed);
        update(snapshot.requests, snapshot.installed, false);
        return;
    }
    if (command === "HOLD") {
        if (!installed.has(name)) fail(`${name} is not installed`);
        if (held.has(name)) fail(`${name} is already held`);
        held.add(name);
        output.push("held " + packageText(installed.get(name)));
        return;
    }
    if (command === "UNHOLD") {
        if (!held.has(name)) fail(`${name} is not held`);
        held.delete(name);
        output.push("released " + name);
        return;
    }
    if (command === "WHY") {
        if (!installed.has(name)) fail(`${name} is not installed`);
        if (requests.some((request) => request.name === name)) {
            output.push(packageText(installed.get(name)) + " is explicitly installed");
            return;
        }
        const queue = requests.map((request) => request.name).sort(),
            parents = new Map(queue.map((packageName) => [packageName, null]));
        for (let i = 0; i < queue.length; i++) {
            const current = queue[i];
            for (const dep of [...installed.get(current).deps].sort((a, b) =>
                compareText(a.name, b.name),
            ))
                if (!parents.has(dep.name)) {
                    parents.set(dep.name, current);
                    queue.push(dep.name);
                }
        }
        const path = [];
        for (let current = name; current !== null; current = parents.get(current))
            path.push(packageText(installed.get(current)));
        output.push(path.reverse().join(" -> "));
        return;
    }
    if (command === "TREE") {
        if (argument !== null && !installed.has(name)) fail(`${name} is not installed`);
        const roots = argument !== null ? [name] : requests.map((request) => request.name).sort(),
            seen = new Set();
        function tree(packageName, raw, prefix, indent) {
            const item = installed.get(packageName),
                body = prefix + packageText(item) + (raw === null ? "" : ` [${raw}]`);
            if (seen.has(packageName)) {
                output.push(body + " (*)");
                return;
            }
            seen.add(packageName);
            output.push(body);
            item.deps.forEach((dep, i) => {
                const last = i === item.deps.length - 1;
                tree(
                    dep.name,
                    dep.raw,
                    indent + (last ? "`-- " : "|-- "),
                    indent + (last ? "    " : "|   "),
                );
            });
        }
        if (!roots.length) output.push("(empty)");
        for (const root of roots)
            tree(root, requests.find((request) => request.name === root)?.raw ?? null, "", "");
        return;
    }
    if (command === "OUTDATED") {
        const lines = [];
        for (const packageName of [...installed.keys()].sort()) {
            const current = installed.get(packageName),
                ranges = requests
                    .filter((request) => request.name === packageName)
                    .map((request) => request.range);
            for (const item of installed.values())
                for (const dep of item.deps) if (dep.name === packageName) ranges.push(dep.range);
            const available = versions(packageName),
                wanted = available.find(
                    (item) =>
                        (!item.yanked || item.version.text === current.version.text) &&
                        ranges.every((range) => satisfies(item.version, range)),
                );
            const latest = available.find((item) => !item.yanked && !item.version.pre.length);
            if (
                wanted.version.text !== current.version.text ||
                (latest !== undefined && compareVersions(latest.version, current.version) > 0)
            )
                lines.push(
                    `${packageName} ${current.version.text} ${wanted.version.text} ${latest?.version.text ?? "-"}`,
                );
        }
        output.push(...(lines.length ? lines : ["all packages are up to date"]));
        return;
    }
    if (command === "LOCK") {
        output.push(
            ...(installed.size
                ? [...installed.keys()].sort().map((name) => packageText(installed.get(name)))
                : ["(empty)"]),
        );
        return;
    }
    if (command === "STATUS") {
        output.push(
            ...(requests.length
                ? requests.map(
                      (request) =>
                          `${request.name} ${request.raw} -> ${installed.get(request.name).version.text}`,
                  )
                : ["no requests"]),
            `${installed.size} installed, ${held.size} held, ${history.length} snapshots`,
        );
        return;
    }
    if (command === "ADVISORY") {
        const [id, rest] = cut(argument),
            [packageName, raw] = cut(rest);
        if (advisories.has(id)) fail(`advisory ${id} already exists`);
        const range = constraint(raw);
        advisories.set(id, { name: packageName, raw, range });
        output.push(`advisory ${id} recorded`);
        return;
    }
    if (command === "AUDIT") {
        const lines = [];
        for (const packageName of [...installed.keys()].sort()) {
            const item = installed.get(packageName),
                ids = applicable(item);
            if (!ids.length) continue;
            const fix = versions(packageName)
                .reverse()
                .find(
                    (candidate) =>
                        compareVersions(candidate.version, item.version) > 0 &&
                        !candidate.version.pre.length &&
                        !candidate.yanked &&
                        !applicable(candidate).length,
                );
            lines.push(
                `${packageText(item)}: ${ids.join(", ")} (${fix === undefined ? "no fix" : "fix: " + fix.version.text})`,
            );
        }
        output.push(...(lines.length ? lines : ["no known vulnerabilities"]));
    }
}
const input = fs.readFileSync(0, "utf8").split(/\r?\n/),
    count = Number(input[0]);
for (const command of input.slice(1, count + 1)) {
    try {
        execute(command);
    } catch (error) {
        output.push(error.message);
    }
}
if (output.length) process.stdout.write(output.join("\n") + "\n");
