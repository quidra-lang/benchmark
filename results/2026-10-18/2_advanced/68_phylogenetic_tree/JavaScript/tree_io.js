'use strict';

const fs = require('node:fs');
const { rootTree } = require('./tree_building');

function real(value, digits) {
    const text = value.toFixed(digits);
    return Number(text) === 0 ? (0).toFixed(digits) : text;
}

function symbols(mask, count) {
    return Array.from({ length: count }, (_, i) => (mask & (2 ** i)) !== 0 ? '*' : '.').join('');
}

function orderedRoot(tree, outgroup, names) {
    const rooted = rootTree(tree, outgroup);
    const minimum = new Map();
    for (const [node, mask] of rooted.masks) {
        const contained = names.filter((name, i) => (mask & (2 ** i)) !== 0);
        contained.sort();
        minimum.set(node, contained[0]);
    }
    for (const children of rooted.children.values()) {
        children.sort((a, b) => minimum.get(a) < minimum.get(b) ? -1 : minimum.get(a) > minimum.get(b) ? 1 : 0);
    }
    return rooted;
}

function newick(tree, outgroup, names, options = {}) {
    const rooted = orderedRoot(tree, outgroup, names);
    function render(node) {
        let text;
        if (node < tree.count) text = names[node];
        else {
            text = '(' + rooted.children.get(node).map(render).join(',') + ')';
            if (node !== rooted.root && options.support) text += options.support.get(rooted.masks.get(node)) || 0;
        }
        if (node !== rooted.root && options.lengths) text += ':' + real(rooted.lengths.get(node), 5);
        return text;
    }
    return render(rooted.root) + ';';
}

function cladogram(tree, outgroup, names, support) {
    const rooted = orderedRoot(tree, outgroup, names);
    const lines = ['*'];
    function visit(node, prefix, last) {
        const label = node < tree.count ? names[node] : '[' + (support.get(rooted.masks.get(node)) || 0) + ']';
        lines.push(prefix + (last ? '`-- ' : '|-- ') + label);
        const children = rooted.children.get(node);
        for (let i = 0; i < children.length; i++) {
            visit(children[i], prefix + (last ? '    ' : '|   '), i === children.length - 1);
        }
    }
    const children = rooted.children.get(rooted.root);
    for (let i = 0; i < children.length; i++) visit(children[i], '', i === children.length - 1);
    return lines;
}

function writeLines(name, lines) {
    fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

module.exports = { real, symbols, orderedRoot, newick, cladogram, writeLines };
