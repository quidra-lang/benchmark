'use strict';

function compareKeys(first, second) {
    for (let index = 0; index < first.length; index++) {
        if (first[index] < second[index]) return -1;
        if (first[index] > second[index]) return 1;
    }
    return 0;
}

function detach(container) {
    if (container.parent !== null) {
        const siblings = container.parent.children;
        siblings.splice(siblings.indexOf(container), 1);
        container.parent = null;
    }
}

function attach(child, parent) {
    detach(child);
    child.parent = parent;
    parent.children.push(child);
}

function isAncestor(first, second) {
    for (let current = second; current !== null; current = current.parent) {
        if (current === first) return true;
    }
    return false;
}

function prune(roots) {
    const replacements = new Map();
    const stack = roots.map(container => ({ container, root: true, exit: false }));
    while (stack.length > 0) {
        const frame = stack.pop();
        const { container, root } = frame;
        if (!frame.exit) {
            stack.push({ container, root, exit: true });
            for (const child of container.children) stack.push({ container: child, root: false, exit: false });
            continue;
        }
        container.children = container.children.flatMap(child => replacements.get(child));
        for (const child of container.children) child.parent = container;
        if (container.message !== null || (root && container.children.length >= 2)) {
            replacements.set(container, [container]);
        } else {
            for (const child of container.children) child.parent = container.parent;
            replacements.set(container, container.children);
        }
    }
    return roots.flatMap(container => replacements.get(container));
}

function containerKey(container) {
    if (container.message !== null) return container.message.key;
    let smallest = container.children[0].message.key;
    for (const child of container.children) {
        if (compareKeys(child.message.key, smallest) < 0) smallest = child.message.key;
    }
    return smallest;
}

function sortForest(roots) {
    const stack = roots.slice();
    while (stack.length > 0) {
        const container = stack.pop();
        container.children.sort((a, b) => compareKeys(containerKey(a), containerKey(b)));
        for (const child of container.children) stack.push(child);
    }
    roots.sort((a, b) => compareKeys(containerKey(a), containerKey(b)));
}

function buildThreads(messages) {
    const table = new Map();
    const created = [];
    function create(id) {
        const container = { id, message: null, parent: null, children: [], subject: null };
        created.push(container);
        return container;
    }
    function get(id) {
        if (!table.has(id)) table.set(id, create(id));
        return table.get(id);
    }
    for (const message of messages) {
        const container = message.id === '' ? create('') : get(message.id);
        container.message = message;
        const references = message.references.map(get);
        for (let index = 0; index + 1 < references.length; index++) {
            const parent = references[index];
            const child = references[index + 1];
            if (child.parent === null && !isAncestor(child, parent)) attach(child, parent);
        }
        detach(container);
        if (references.length > 0 && !isAncestor(container, references.at(-1))) attach(container, references.at(-1));
    }
    let roots = prune(created.filter(container => container.parent === null));
    sortForest(roots);
    const groups = new Map();
    for (const root of roots) {
        const subject = (root.message ?? root.children[0].message).baseSubject;
        if (subject === '') continue;
        if (!groups.has(subject)) groups.set(subject, []);
        groups.get(subject).push(root);
    }
    const retained = new Set(roots);
    for (const [subject, group] of groups) {
        if (group.length < 2) continue;
        let target = group.find(container => container.message === null);
        if (target === undefined) {
            const originals = group.filter(container => !container.message.reply);
            if (originals.length === 1) target = originals[0];
            else {
                target = create('');
                target.subject = subject;
                retained.add(target);
            }
        }
        for (const container of group) {
            if (container === target) continue;
            retained.delete(container);
            if (container.message !== null) attach(container, target);
            else for (const child of container.children.slice()) attach(child, target);
        }
    }
    roots = [...retained];
    sortForest(roots);
    return roots;
}

module.exports = { buildThreads };
