const fs = require('node:fs');

const output = [];
const commits = new Map();
const branches = new Map();
const tags = new Map();
const stashes = [];
const patterns = [];
let sequence = 0;
let working = new Map();
let index = new Map();
let conflicts = new Set();
let operation = null;
let branch = 'main';
let detached;

function paths(...trees) {
    return [...new Set(trees.flatMap(tree => [...tree.keys()]))].sort();
}
function different(a, b) {
    return paths(a, b).filter(path => a.get(path) !== b.get(path));
}
function equal(a, b) { return different(a, b).length === 0; }
function match(target, source, path) {
    if (source.has(path)) target.set(path, source.get(path));
    else target.delete(path);
}
function fail(message) { throw new Error(`error: ${message}`); }
function create(parents, tree, message) {
    const s = sequence++;
    let canonical = `commit ${s}\n`;
    for (const parent of parents) canonical += `parent ${parent.id}\n`;
    for (const path of [...tree.keys()].sort()) canonical += `file ${path} ${tree.get(path)}\n`;
    canonical += `message ${message}\n`;
    let hash = 0;
    for (let i = 0; i < canonical.length; i++) hash = (hash * 131 + canonical.charCodeAt(i)) % 2147483647;
    const commit = {
        id: hash.toString(16).padStart(8, '0'), sequence: s,
        parents: [...parents], tree: new Map(tree), message
    };
    commits.set(commit.id, commit);
    return commit;
}
const root = create([], new Map(), 'init');
branches.set('main', root);
detached = root;
function head() { return branch === null ? detached : branches.get(branch); }
function move(commit) {
    if (branch === null) detached = commit;
    else branches.set(branch, commit);
}
function record(parents, tree, message) {
    const commit = create(parents, tree, message);
    const old = parents[0].tree;
    let added = 0, modified = 0, deleted = 0;
    for (const path of different(old, tree)) {
        if (!old.has(path)) added++;
        else if (!tree.has(path)) deleted++;
        else modified++;
    }
    move(commit);
    output.push(`[${branch ?? 'detached HEAD'} ${commit.id}] ${message} (${added} added, ${modified} modified, ${deleted} deleted)`);
    return commit;
}
function resolve(rev) {
    const [anchor, count] = rev.split('~');
    let commit = anchor === 'HEAD' ? head() : branches.get(anchor) ?? tags.get(anchor) ?? commits.get(anchor);
    if (!commit) fail(`unknown revision '${rev}'`);
    for (let i = 0; i < Number(count ?? 0); i++) {
        if (commit.parents.length === 0) fail(`unknown revision '${rev}'`);
        commit = commit.parents[0];
    }
    return commit;
}
function distances(start) {
    const result = new Map([[start, 0]]);
    const queue = [start];
    for (let i = 0; i < queue.length; i++) {
        const commit = queue[i];
        for (const parent of commit.parents) if (!result.has(parent)) {
            result.set(parent, result.get(commit) + 1);
            queue.push(parent);
        }
    }
    return result;
}
function ancestor(a, b) { return distances(b).has(a); }
function mergeBase(a, b) {
    const da = distances(a), db = distances(b);
    const common = [...da.keys()].filter(commit => db.has(commit));
    const candidates = common.filter(commit => !common.some(other => other !== commit && ancestor(commit, other)));
    candidates.sort((x, y) => Math.max(da.get(x), db.get(x)) - Math.max(da.get(y), db.get(y)) || y.sequence - x.sequence);
    return candidates[0];
}
function summary(commit) {
    const refs = [];
    if (head() === commit) refs.push(branch === null ? 'HEAD' : `HEAD -> ${branch}`);
    for (const name of [...branches.keys()].sort()) if (name !== branch && branches.get(name) === commit) refs.push(name);
    for (const name of [...tags.keys()].sort()) if (tags.get(name) === commit) refs.push(`tag: ${name}`);
    return `${commit.id}${refs.length ? ` (${refs.join(', ')})` : ''} ${commit.message}`;
}
function changes(a, b) {
    const changed = different(a, b);
    if (!changed.length) output.push('(no changes)');
    for (const path of changed) {
        if (!a.has(path)) output.push(`A ${path}: ${b.get(path)}`);
        else if (!b.has(path)) output.push(`D ${path}: ${a.get(path)}`);
        else output.push(`M ${path}: ${a.get(path)} -> ${b.get(path)}`);
    }
}
function inProgress() { if (operation) fail(`${operation.kind} in progress`); }
function dirty() {
    return !equal(index, head().tree) || [...index.keys()].some(path => working.get(path) !== index.get(path));
}
function uncommitted() { if (dirty()) fail('uncommitted changes'); }
function overwrite(check) {
    const h = head().tree;
    for (const path of [...new Set(check)].sort()) {
        if (index.get(path) !== h.get(path) || working.get(path) !== h.get(path)) {
            fail(`local changes to '${path}' would be overwritten`);
        }
    }
}
function switchTree(tree) {
    const changed = different(head().tree, tree);
    overwrite(changed);
    for (const path of changed) { match(index, tree, path); match(working, tree, path); }
}
function merge(base, ours, theirs) {
    const tree = new Map(), found = [], contents = new Map();
    for (const path of paths(base, ours, theirs)) {
        const b = base.get(path), o = ours.get(path), t = theirs.get(path);
        if (t === b || o === t) match(tree, ours, path);
        else if (o === b) match(tree, theirs, path);
        else {
            found.push(path);
            match(tree, ours, path);
            contents.set(path, `<<<<<<< ${o ?? '(deleted)'} ======= ${t ?? '(deleted)'} >>>>>>>`);
        }
    }
    return { tree, conflicts: found, contents };
}
function apply(base, theirs, kind, target, message, parents, mergeCommit) {
    const result = merge(base, head().tree, theirs);
    const changed = different(head().tree, result.tree);
    overwrite([...changed, ...result.conflicts]);
    if (kind === 'merge') output.push(`Merge base ${mergeCommit.id}`);
    if (kind !== 'merge' && !result.conflicts.length && !changed.length) {
        output.push('nothing to commit');
        return;
    }
    for (const path of changed) { match(index, result.tree, path); match(working, result.tree, path); }
    if (!result.conflicts.length) { record(parents, result.tree, message); return; }
    for (const path of result.conflicts) {
        working.set(path, result.contents.get(path));
        output.push(`CONFLICT ${path}`);
    }
    conflicts = new Set(result.conflicts);
    operation = { kind, target };
    output.push(kind === 'merge' ? 'Automatic merge failed; fix conflicts and then commit the result.' :
        kind === 'revert' ? `error: could not revert ${target.id}` : `error: could not apply ${target.id}`);
}
function glob(pattern, path) {
    let row = Array(path.length + 1).fill(false);
    row[0] = true;
    for (const ch of pattern) {
        const next = Array(path.length + 1).fill(false);
        if (ch === '*') next[0] = row[0];
        for (let i = 1; i <= path.length; i++) {
            next[i] = ch === '*' ? row[i] || next[i - 1] : row[i - 1] && (ch === '?' || ch === path[i - 1]);
        }
        row = next;
    }
    return row[path.length];
}
function ignored(path) {
    return !index.has(path) && !conflicts.has(path) && patterns.some(pattern => glob(pattern, path));
}
function pathspec(path) { return fail(`pathspec '${path}' did not match any files`); }
function existingPath(tree, path, rev) {
    if (!tree.has(path)) fail(`path '${path}' does not exist in '${rev}'`);
    return tree.get(path);
}
function reachable(roots) {
    const result = new Set();
    for (const commit of roots) for (const item of distances(commit).keys()) result.add(item);
    return result;
}
function execute(line) {
    const words = line.split(' '), command = words[0], arg = words[1];
    switch (command) {
        case 'WRITE': working.set(arg, line.slice(line.indexOf(' ', 6) + 1)); break;
        case 'REMOVE':
            if (!working.has(arg)) fail(`no such file '${arg}'`);
            working.delete(arg);
            break;
        case 'ADD':
            if (arg === 'ALL') {
                const selected = paths(working, index).filter(path => !ignored(path));
                for (const path of selected) match(index, working, path);
                conflicts.clear();
            } else {
                if (working.has(arg) && ignored(arg)) fail(`path '${arg}' is ignored`);
                if (!working.has(arg) && !index.has(arg) && !conflicts.has(arg)) pathspec(arg);
                match(index, working, arg);
                conflicts.delete(arg);
            }
            break;
        case 'RM':
            if (!index.has(arg)) pathspec(arg);
            index.delete(arg); working.delete(arg); conflicts.delete(arg);
            break;
        case 'UNSTAGE':
            if (!index.has(arg) && !head().tree.has(arg)) pathspec(arg);
            match(index, head().tree, arg);
            break;
        case 'RESTORE':
            if (words.length === 2) {
                if (!index.has(arg)) pathspec(arg);
                working.set(arg, index.get(arg));
            } else {
                const tree = resolve(words[2]).tree;
                const value = existingPath(tree, arg, words[2]);
                index.set(arg, value); working.set(arg, value); conflicts.delete(arg);
            }
            break;
        case 'IGNORE': patterns.push(arg); break;
        case 'COMMIT': {
            if (conflicts.size) fail('unresolved conflicts');
            const parents = operation?.kind === 'merge' ? [head(), operation.target] : [head()];
            if (parents.length === 1 && equal(index, head().tree)) { output.push('nothing to commit'); break; }
            record(parents, index, line.slice(7));
            operation = null;
            break;
        }
        case 'AMEND':
            inProgress();
            if (!head().parents.length) fail('cannot amend the root commit');
            record(head().parents, index, line.slice(6));
            break;
        case 'STATUS': {
            output.push(branch === null ? `HEAD detached at ${head().id}` : `On branch ${branch}`);
            if (operation) {
                const verb = operation.kind === 'merge' ? 'Merging' : operation.kind === 'revert' ? 'Reverting' : 'Cherry-picking';
                output.push(`${verb} ${operation.target.id}`);
            }
            const before = output.length;
            const all = [...new Set([...paths(head().tree, index, working), ...conflicts])].sort();
            for (const path of all) {
                if (conflicts.has(path)) { output.push(`UU ${path}`); continue; }
                if (index.has(path)) {
                    const x = !head().tree.has(path) ? 'A' : head().tree.get(path) !== index.get(path) ? 'M' : '.';
                    const y = !working.has(path) ? 'D' : working.get(path) !== index.get(path) ? 'M' : '.';
                    if (x !== '.' || y !== '.') output.push(`${x}${y} ${path}`);
                } else {
                    if (head().tree.has(path)) output.push(`D. ${path}`);
                    if (working.has(path) && !ignored(path)) output.push(`?? ${path}`);
                }
            }
            if (output.length === before) output.push('nothing to commit, working tree clean');
            break;
        }
        case 'LS': {
            const tree = arg ? resolve(arg).tree : working;
            if (!tree.size) output.push('(empty)');
            for (const path of [...tree.keys()].sort()) output.push(`${path} ${tree.get(path)}`);
            break;
        }
        case 'CAT':
            if (words.length === 3) output.push(existingPath(resolve(words[2]).tree, arg, words[2]));
            else {
                if (!working.has(arg)) fail(`no such file '${arg}'`);
                output.push(working.get(arg));
            }
            break;
        case 'DIFF':
            if (arg === 'STAGED') changes(head().tree, index);
            else if (arg) { const a = resolve(arg); const b = resolve(words[2]); changes(a.tree, b.tree); }
            else changes(index, new Map([...working].filter(([path]) => index.has(path))));
            break;
        case 'LOG': {
            let current = head();
            for (let i = 0; i < (arg ? Number(arg) : Infinity); i++) {
                output.push(summary(current));
                if (!current.parents.length) break;
                current = current.parents[0];
            }
            break;
        }
        case 'SHOW': {
            const commit = resolve(arg ?? 'HEAD');
            output.push(`commit ${summary(commit)}`, `parents: ${commit.parents.length ? commit.parents.map(parent => parent.id).join(' ') : 'none'}`);
            changes(commit.parents[0]?.tree ?? new Map(), commit.tree);
            break;
        }
        case 'BLAME': {
            const value = existingPath(head().tree, arg, 'HEAD');
            let commit = head();
            while (commit.parents.length && commit.parents[0].tree.get(arg) === value) commit = commit.parents[0];
            output.push(`${commit.id} (${commit.message}) ${value}`);
            break;
        }
        case 'BRANCH': case 'TAG': {
            const refs = command === 'BRANCH' ? branches : tags;
            const noun = command === 'BRANCH' ? 'branch' : 'tag';
            if (arg === '-d') {
                const name = words[2], commit = refs.get(name);
                if (!commit) fail(`no such ${noun} '${name}'`);
                if (command === 'BRANCH') {
                    if (branch === name) fail(`cannot delete current branch '${name}'`);
                    if (!ancestor(commit, head())) fail(`branch '${name}' is not fully merged`);
                }
                refs.delete(name);
                output.push(`Deleted ${noun} ${name} (was ${commit.id})`);
            } else {
                if (refs.has(arg)) fail(`${noun} '${arg}' already exists`);
                const commit = resolve(words[2] ?? 'HEAD');
                refs.set(arg, commit);
                output.push(`Created ${noun} ${arg} at ${commit.id}`);
            }
            break;
        }
        case 'BRANCHES':
            if (branch === null) output.push(`* (HEAD detached at ${head().id})`);
            for (const name of [...branches.keys()].sort()) {
                const commit = branches.get(name);
                output.push(`${branch === name ? '*' : ' '} ${name} ${commit.id} ${commit.message}`);
            }
            break;
        case 'TAGS':
            if (!tags.size) output.push('(no tags)');
            for (const name of [...tags.keys()].sort()) {
                const commit = tags.get(name);
                output.push(`${name} ${commit.id} ${commit.message}`);
            }
            break;
        case 'SWITCH': {
            const commit = branches.get(arg);
            if (!commit) fail(`no such branch '${arg}'`);
            if (branch === arg) { output.push(`Already on '${arg}'`); break; }
            inProgress(); switchTree(commit.tree); branch = arg;
            output.push(`Switched to branch '${arg}'`);
            break;
        }
        case 'DETACH': {
            const commit = resolve(arg);
            inProgress(); switchTree(commit.tree); branch = null; detached = commit;
            output.push(`HEAD is now at ${commit.id} ${commit.message}`);
            break;
        }
        case 'MERGE': {
            const target = resolve(arg);
            inProgress();
            const old = head();
            if (ancestor(target, old)) { output.push('Already up to date'); break; }
            if (ancestor(old, target)) {
                switchTree(target.tree); move(target);
                output.push(`Fast-forward ${old.id}..${target.id}`);
                break;
            }
            uncommitted();
            const base = mergeBase(old, target);
            apply(base.tree, target.tree, 'merge', target, `Merge ${arg}`, [old, target], base);
            break;
        }
        case 'MERGEBASE': {
            const a = resolve(arg), b = resolve(words[2]);
            output.push(mergeBase(a, b).id);
            break;
        }
        case 'REBASE': {
            const onto = resolve(arg);
            inProgress();
            if (ancestor(onto, head())) { output.push('Already up to date'); break; }
            uncommitted();
            const list = [];
            let current = head();
            while (!ancestor(current, onto)) { list.push(current); current = current.parents[0]; }
            list.reverse();
            const picks = new Map();
            let tree = onto.tree;
            for (const commit of list) {
                const result = merge(commit.parents[0].tree, tree, commit.tree);
                if (result.conflicts.length) fail(`could not rebase ${commit.id}: conflict in '${result.conflicts[0]}'`);
                if (!equal(result.tree, tree)) { picks.set(commit, result.tree); tree = result.tree; }
            }
            switchTree(tree);
            let target = onto;
            for (const commit of list) {
                if (picks.has(commit)) {
                    const next = create([target], picks.get(commit), commit.message);
                    output.push(`pick ${commit.id} -> ${next.id} ${commit.message}`);
                    target = next;
                } else output.push(`skip ${commit.id} ${commit.message}`);
            }
            move(target);
            output.push(`HEAD is now at ${target.id} ${target.message}`);
            break;
        }
        case 'RESET': {
            const target = resolve(words[2]), tree = target.tree;
            if (arg === 'HARD') {
                const all = [...new Set([...paths(index, tree), ...conflicts])];
                for (const path of all) match(working, tree, path);
            }
            if (arg !== 'SOFT') index = new Map(tree);
            move(target); conflicts.clear(); operation = null;
            output.push(`HEAD is now at ${target.id} ${target.message}`);
            break;
        }
        case 'REVERT': case 'CHERRYPICK': {
            const target = resolve(arg);
            inProgress(); uncommitted();
            const parentTree = target.parents[0]?.tree ?? new Map();
            if (command === 'REVERT') apply(target.tree, parentTree, 'revert', target, `Revert "${target.message}"`, [head()]);
            else apply(parentTree, target.tree, 'cherry-pick', target, target.message, [head()]);
            break;
        }
        case 'STASH':
            if (arg === 'LIST') {
                if (!stashes.length) output.push('(no stash entries)');
                stashes.forEach((stash, i) => output.push(`stash@{${i}}: ${stash.label}`));
            } else if (arg === 'DROP') {
                if (!stashes.length) fail('no stash entries');
                output.push(`Dropped stash@{0}: ${stashes.shift().label}`);
            } else if (arg === 'POP') {
                if (!stashes.length) fail('no stash entries');
                inProgress(); uncommitted();
                const stash = stashes[0], result = merge(stash.base.tree, head().tree, stash.tree);
                if (result.conflicts.length) fail(`stash conflict in '${result.conflicts[0]}'`);
                const changed = different(head().tree, result.tree);
                overwrite(changed);
                for (const path of changed) match(working, result.tree, path);
                stashes.shift();
                output.push(`Restored stash@{0}: ${stash.label}`);
                changes(head().tree, result.tree);
            } else {
                inProgress();
                if (!dirty()) { output.push('No local changes to save'); break; }
                const tree = new Map(), h = head();
                for (const path of paths(index, h.tree)) {
                    if (working.has(path)) tree.set(path, working.get(path));
                    match(working, h.tree, path);
                }
                index = new Map(h.tree);
                const label = `WIP on ${branch ?? '(no branch)'}: ${h.id} ${h.message}`;
                stashes.unshift({ label, base: h, tree });
                output.push(`Saved stash@{0}: ${label}`);
            }
            break;
        case 'GRAPH': {
            const all = [...reachable([head(), ...branches.values(), ...tags.values()])].sort((a, b) => b.sequence - a.sequence);
            let lanes = [];
            for (const commit of all) {
                if (!lanes.includes(commit)) lanes.push(commit);
                const k = lanes.indexOf(commit);
                const symbols = lanes.map((item, i) => i === k ? '*' : item === commit ? '/' : '|');
                output.push(`${symbols.join(' ')} ${summary(commit)}`);
                lanes = lanes.filter((item, i) => item !== commit || i === k);
                if (!commit.parents.length) lanes.splice(k, 1);
                else {
                    lanes[k] = commit.parents[0];
                    if (commit.parents.length === 2 && !lanes.includes(commit.parents[1])) lanes.splice(k + 1, 0, commit.parents[1]);
                }
            }
            break;
        }
        case 'DESCRIBE': {
            const target = resolve(arg ?? 'HEAD'), distance = distances(target);
            const names = [...tags.keys()].filter(name => distance.has(tags.get(name)));
            names.sort((a, b) => distance.get(tags.get(a)) - distance.get(tags.get(b)) || (a < b ? -1 : a > b ? 1 : 0));
            if (!names.length) fail(`no tag can describe '${target.id}'`);
            const name = names[0], d = distance.get(tags.get(name));
            output.push(d === 0 ? name : `${name}-${d}-g${target.id}`);
            break;
        }
        case 'GC': {
            const roots = [head(), ...branches.values(), ...tags.values(), ...stashes.map(stash => stash.base)];
            if (operation) roots.push(operation.target);
            const keep = reachable(roots);
            let removed = 0;
            for (const [id, commit] of commits) if (!keep.has(commit)) { commits.delete(id); removed++; }
            output.push(`Removed unreachable commits: ${removed}`);
            break;
        }
    }
}
for (const line of fs.readFileSync(0, 'utf8').split(/\r?\n/)) {
    if (line === 'EXIT') break;
    if (!line) continue;
    try { execute(line); }
    catch (error) { output.push(error.message); }
}
if (output.length) process.stdout.write(output.join('\n') + '\n');
