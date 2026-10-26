const fs = require("node:fs");

let rectangles = new Map();
const rules = new Map(),
    history = [],
    output = [];
function fail(message) {
    throw new Error("error: " + message);
}
function compare(a, b) {
    return a < b ? -1 : a > b ? 1 : 0;
}
function ordered() {
    return [...rectangles.values()].sort((a, b) => compare(a.name, b.name));
}
function rectangle(name) {
    const value = rectangles.get(name);
    if (value === undefined) fail("unknown rectangle " + name);
    return value;
}
function onLayer(layer, required = true) {
    const result = ordered().filter((rect) => rect.layer === layer);
    if (required && !result.length) fail("no rectangles on " + layer);
    return result;
}
function notation(rect) {
    return `(${rect.x1},${rect.y1})-(${rect.x2},${rect.y2})`;
}
function point(x, y) {
    return `(${x},${y})`;
}
function area(rect) {
    return (rect.x2 - rect.x1) * (rect.y2 - rect.y1);
}
function bounds(rects) {
    return {
        x1: Math.min(...rects.map((rect) => rect.x1)),
        y1: Math.min(...rects.map((rect) => rect.y1)),
        x2: Math.max(...rects.map((rect) => rect.x2)),
        y2: Math.max(...rects.map((rect) => rect.y2)),
    };
}
function checkBounds(rect) {
    if ([rect.x1, rect.y1, rect.x2, rect.y2].some((value) => Math.abs(value) > 10000))
        fail("out of bounds");
}
function margins(outer, inner) {
    return [inner.x1 - outer.x1, inner.y1 - outer.y1, outer.x2 - inner.x2, outer.y2 - inner.y2];
}
function contains(outer, inner) {
    return margins(outer, inner).every((value) => value >= 0);
}
function relation(a, b) {
    const common = {
        x1: Math.max(a.x1, b.x1),
        y1: Math.max(a.y1, b.y1),
        x2: Math.min(a.x2, b.x2),
        y2: Math.min(a.y2, b.y2),
    };
    const ox = common.x2 - common.x1,
        oy = common.y2 - common.y1;
    const kind =
        ox < 0 || oy < 0
            ? "separated"
            : ox === 0 && oy === 0
              ? "corner"
              : ox === 0 || oy === 0
                ? "edge"
                : "overlap";
    return {
        common,
        ox,
        oy,
        kind,
        gap: Math.max(0, -ox, -oy),
        direction: ox < 0 && oy < 0 ? "diagonal" : ox < 0 ? "x" : "y",
    };
}
function connected(a, b) {
    const kind = relation(a, b).kind;
    return kind === "overlap" || kind === "edge";
}
function pair(a, b) {
    const first = rectangle(a),
        second = rectangle(b);
    if (a === b) fail("same rectangle " + a);
    return [first, second];
}
function decimal(numerator, denominator) {
    const value = Math.floor((100 * numerator) / denominator);
    return Math.floor(value / 100) + "." + String(value % 100).padStart(2, "0");
}
class Coverage {
    constructor(rects) {
        this.x = [...new Set(rects.flatMap((rect) => [rect.x1, rect.x2]))].sort((a, b) => a - b);
        this.y = [...new Set(rects.flatMap((rect) => [rect.y1, rect.y2]))].sort((a, b) => a - b);
        this.nx = this.x.length - 1;
        this.ny = this.y.length - 1;
        const xi = new Map(this.x.map((value, i) => [value, i])),
            yi = new Map(this.y.map((value, i) => [value, i]));
        const diff = Array.from({ length: this.y.length }, () => Array(this.x.length).fill(0));
        for (const rect of rects) {
            const a = xi.get(rect.x1),
                b = xi.get(rect.x2),
                c = yi.get(rect.y1),
                d = yi.get(rect.y2);
            diff[c][a]++;
            diff[c][b]--;
            diff[d][a]--;
            diff[d][b]++;
        }
        for (let j = 0; j < this.y.length; j++)
            for (let i = 0; i < this.x.length; i++)
                diff[j][i] +=
                    (j ? diff[j - 1][i] : 0) +
                    (i ? diff[j][i - 1] : 0) -
                    (i && j ? diff[j - 1][i - 1] : 0);
        this.counts = diff.slice(0, this.ny).map((row) => row.slice(0, this.nx));
        this.prefix = Array.from({ length: this.ny + 1 }, () => Array(this.nx + 1).fill(0));
        for (let j = 0; j < this.ny; j++)
            for (let i = 0; i < this.nx; i++)
                this.prefix[j + 1][i + 1] =
                    this.prefix[j][i + 1] +
                    this.prefix[j + 1][i] -
                    this.prefix[j][i] +
                    (this.counts[j][i] > 0
                        ? (this.x[i + 1] - this.x[i]) * (this.y[j + 1] - this.y[j])
                        : 0);
    }
    covered(i, j) {
        return i >= 0 && i < this.nx && j >= 0 && j < this.ny && this.counts[j][i] > 0;
    }
    area(threshold = 1) {
        let total = 0;
        for (let j = 0; j < this.ny; j++)
            for (let i = 0; i < this.nx; i++)
                if (this.counts[j][i] >= threshold)
                    total += (this.x[i + 1] - this.x[i]) * (this.y[j + 1] - this.y[j]);
        return total;
    }
    perimeter() {
        let total = 0;
        for (let j = 0; j < this.ny; j++)
            for (let i = 0; i < this.nx; i++)
                if (this.covered(i, j)) {
                    if (!this.covered(i - 1, j)) total += this.y[j + 1] - this.y[j];
                    if (!this.covered(i + 1, j)) total += this.y[j + 1] - this.y[j];
                    if (!this.covered(i, j - 1)) total += this.x[i + 1] - this.x[i];
                    if (!this.covered(i, j + 1)) total += this.x[i + 1] - this.x[i];
                }
        return total;
    }
    coordinate(values, point) {
        let low = 0,
            high = values.length;
        while (low < high) {
            const middle = Math.floor((low + high) / 2);
            if (values[middle] <= point) low = middle + 1;
            else high = middle;
        }
        return low - 1;
    }
    integral(x, y) {
        x = Math.max(this.x[0], Math.min(x, this.x.at(-1)));
        y = Math.max(this.y[0], Math.min(y, this.y.at(-1)));
        const i = this.coordinate(this.x, x),
            j = this.coordinate(this.y, y),
            dx = x - this.x[i],
            dy = y - this.y[j];
        let value = this.prefix[j][i];
        if (dx > 0)
            value +=
                ((this.prefix[j][i + 1] - this.prefix[j][i]) / (this.x[i + 1] - this.x[i])) * dx;
        if (dy > 0)
            value +=
                ((this.prefix[j + 1][i] - this.prefix[j][i]) / (this.y[j + 1] - this.y[j])) * dy;
        if (dx > 0 && dy > 0 && this.covered(i, j)) value += dx * dy;
        return value;
    }
    window(rect) {
        return (
            this.integral(rect.x2, rect.y2) -
            this.integral(rect.x1, rect.y2) -
            this.integral(rect.x2, rect.y1) +
            this.integral(rect.x1, rect.y1)
        );
    }
    empty() {
        let best = null,
            bestArea = 0;
        for (let left = 0; left < this.nx; left++) {
            const blocked = Array(this.ny).fill(false);
            for (let right = left + 1; right <= this.nx; right++) {
                for (let j = 0; j < this.ny; j++) blocked[j] ||= this.covered(right - 1, j);
                for (let bottom = 0; bottom < this.ny;) {
                    if (blocked[bottom]) {
                        bottom++;
                        continue;
                    }
                    let top = bottom + 1;
                    while (top < this.ny && !blocked[top]) top++;
                    const candidate = {
                            x1: this.x[left],
                            y1: this.y[bottom],
                            x2: this.x[right],
                            y2: this.y[top],
                        },
                        size = area(candidate);
                    if (
                        size > bestArea ||
                        (size === bestArea &&
                            (best === null ||
                                candidate.x1 < best.x1 ||
                                (candidate.x1 === best.x1 &&
                                    (candidate.y1 < best.y1 ||
                                        (candidate.y1 === best.y1 &&
                                            candidate.x2 - candidate.x1 < best.x2 - best.x1)))))
                    ) {
                        best = candidate;
                        bestArea = size;
                    }
                    bottom = top;
                }
            }
        }
        return best;
    }
    holes() {
        const visited = Array.from({ length: this.ny }, () => Array(this.nx).fill(false)),
            result = [];
        for (let j = 0; j < this.ny; j++)
            for (let i = 0; i < this.nx; i++)
                if (!visited[j][i] && !this.covered(i, j)) {
                    const queue = [[i, j]],
                        cells = [];
                    let boundary = false,
                        total = 0;
                    visited[j][i] = true;
                    for (let at = 0; at < queue.length; at++) {
                        const [x, y] = queue[at];
                        cells.push({
                            x1: this.x[x],
                            y1: this.y[y],
                            x2: this.x[x + 1],
                            y2: this.y[y + 1],
                        });
                        total += area(cells.at(-1));
                        if (x === 0 || y === 0 || x + 1 === this.nx || y + 1 === this.ny)
                            boundary = true;
                        for (const [a, b] of [
                            [x - 1, y],
                            [x + 1, y],
                            [x, y - 1],
                            [x, y + 1],
                        ])
                            if (
                                a >= 0 &&
                                a < this.nx &&
                                b >= 0 &&
                                b < this.ny &&
                                !visited[b][a] &&
                                !this.covered(a, b)
                            ) {
                                visited[b][a] = true;
                                queue.push([a, b]);
                            }
                    }
                    if (!boundary)
                        result.push({
                            box: bounds(cells),
                            area: total,
                            x: this.x[i],
                            y: this.y[j],
                        });
                }
        return result.sort((a, b) => a.y - b.y || a.x - b.x);
    }
    pieces() {
        let active = new Map();
        const result = [];
        for (let j = 0; j < this.ny; j++) {
            const next = new Map();
            for (let i = 0; i < this.nx;) {
                if (!this.covered(i, j)) {
                    i++;
                    continue;
                }
                const left = i;
                while (i < this.nx && this.covered(i, j)) i++;
                const key = this.x[left] + ":" + this.x[i],
                    old = active.get(key);
                const rect = old ?? {
                    x1: this.x[left],
                    y1: this.y[j],
                    x2: this.x[i],
                    y2: this.y[j],
                };
                rect.y2 = this.y[j + 1];
                next.set(key, rect);
            }
            for (const [key, rect] of active) if (!next.has(key)) result.push(rect);
            active = next;
        }
        result.push(...active.values());
        return result.sort((a, b) => a.y1 - b.y1 || a.x1 - b.x1);
    }
}
function nets(rects) {
    const seen = new Set(),
        result = [];
    for (const first of rects)
        if (!seen.has(first.name)) {
            const queue = [first];
            seen.add(first.name);
            for (let i = 0; i < queue.length; i++)
                for (const next of rects)
                    if (!seen.has(next.name) && connected(queue[i], next)) {
                        seen.add(next.name);
                        queue.push(next);
                    }
            result.push(queue.sort((a, b) => compare(a.name, b.name)));
        }
    return result;
}
function violations(rects, spacing) {
    const result = [];
    for (let i = 0; i < rects.length; i++)
        for (let j = i + 1; j < rects.length; j++) {
            const rel = relation(rects[i], rects[j]);
            if (rel.kind === "corner" || (rel.kind === "separated" && rel.gap < spacing))
                result.push({
                    a: rects[i].name,
                    b: rects[j].name,
                    gap: rel.gap,
                    direction: rel.kind === "corner" ? "corner" : rel.direction,
                });
        }
    return result.sort((a, b) => a.gap - b.gap || compare(a.a, b.a) || compare(a.b, b.b));
}
function violationLines(items) {
    return items.map((item) => `${item.a} ${item.b} gap ${item.gap} ${item.direction}`);
}
function execute(line) {
    const [command, ...args] = line.split(" "),
        a = args[0],
        b = args[1];
    if (["ADD", "COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE"].includes(command)) {
        const before = new Map(rectangles);
        if (command === "ADD") {
            if (rectangles.has(a)) fail("duplicate rectangle " + a);
            const [x1, y1, x2, y2] = args.slice(2).map(Number),
                rect = { name: a, layer: b, x1, y1, x2, y2 };
            if (x1 >= x2 || y1 >= y2) fail("invalid rectangle");
            checkBounds(rect);
            rectangles.set(a, rect);
            output.push(`added ${a} ${b} ${notation(rect)}`);
        } else {
            const old = rectangle(a);
            if (command === "COPY" || command === "MOVE") {
                if (command === "COPY" && rectangles.has(b)) fail("duplicate rectangle " + b);
                const offset = command === "COPY" ? 2 : 1,
                    dx = Number(args[offset]),
                    dy = Number(args[offset + 1]);
                const rect = {
                    ...old,
                    name: command === "COPY" ? b : a,
                    x1: old.x1 + dx,
                    y1: old.y1 + dy,
                    x2: old.x2 + dx,
                    y2: old.y2 + dy,
                };
                checkBounds(rect);
                rectangles.set(rect.name, rect);
                output.push(
                    command === "COPY"
                        ? `copied ${a} to ${b} ${notation(rect)}`
                        : `moved ${a} to ${notation(rect)}`,
                );
            } else if (command === "RESIZE") {
                const w = Number(b),
                    h = Number(args[2]);
                if (w <= 0 || h <= 0) fail("invalid size");
                const rect = { ...old, x2: old.x1 + w, y2: old.y1 + h };
                checkBounds(rect);
                rectangles.set(a, rect);
                output.push(`resized ${a} to ${notation(rect)}`);
            } else if (command === "SPLIT") {
                const position = Number(args[2]),
                    name = args[3];
                if (rectangles.has(name)) fail("duplicate rectangle " + name);
                if (
                    b === "x"
                        ? position <= old.x1 || position >= old.x2
                        : position <= old.y1 || position >= old.y2
                )
                    fail("cut outside " + a);
                const first = { ...old, ...(b === "x" ? { x2: position } : { y2: position }) },
                    second = { ...old, name, ...(b === "x" ? { x1: position } : { y1: position }) };
                rectangles.set(a, first);
                rectangles.set(name, second);
                output.push(
                    `split ${a} at ${b}=${position}: ${a} ${notation(first)}, ${name} ${notation(second)}`,
                );
            } else if (command === "LAYER") {
                if (old.layer === b) fail("already on " + b);
                rectangles.set(a, { ...old, layer: b });
                output.push(`layer ${a} ${old.layer} -> ${b}`);
            } else {
                rectangles.delete(a);
                output.push("deleted " + a);
            }
        }
        history.push({ rectangles: before, line });
        return;
    }
    if (command === "UNDO") {
        if (!history.length) fail("nothing to undo");
        const previous = history.pop();
        rectangles = previous.rectangles;
        output.push("undo: " + previous.line);
        return;
    }
    if (command === "LIST") {
        output.push("rectangles: " + rectangles.size);
        for (const rect of ordered())
            output.push(
                `${rect.name} ${rect.layer} ${notation(rect)} ${rect.x2 - rect.x1}x${rect.y2 - rect.y1}`,
            );
        return;
    }
    if (command === "INFO") {
        const rect = rectangle(a),
            others = ordered().filter((other) => other.name !== a),
            same = others.filter((other) => other.layer === rect.layer);
        output.push(
            `${a} ${rect.layer} ${notation(rect)} ${rect.x2 - rect.x1}x${rect.y2 - rect.y1} area ${area(rect)}`,
        );
        for (const [label, list] of [
            ["overlaps", same.filter((other) => relation(rect, other).kind === "overlap")],
            ["touches", same.filter((other) => relation(rect, other).kind === "edge")],
            ["corners", same.filter((other) => relation(rect, other).kind === "corner")],
            ["encloses", others.filter((other) => contains(rect, other))],
            ["enclosed by", others.filter((other) => contains(other, rect))],
        ])
            output.push(label + ": " + (list.map((other) => other.name).join(" ") || "none"));
        return;
    }
    if (command === "LAYERS") {
        const layers = [...new Set(ordered().map((rect) => rect.layer))].sort();
        output.push("layers: " + layers.length);
        for (const layer of layers) {
            const rects = onLayer(layer);
            output.push(
                `${layer}: ${rects.length} rectangles, area ${new Coverage(rects).area()}, nets ${nets(rects).length}`,
            );
        }
        return;
    }
    if (command === "OVERLAPS") {
        const layers =
                a === undefined ? [...new Set(ordered().map((rect) => rect.layer))].sort() : [a],
            found = [];
        if (a !== undefined) onLayer(a);
        for (const layer of layers) {
            const rects = onLayer(layer);
            for (let i = 0; i < rects.length; i++)
                for (let j = i + 1; j < rects.length; j++) {
                    const rel = relation(rects[i], rects[j]);
                    if (rel.kind === "overlap")
                        found.push(
                            `${a === undefined ? layer + " " : ""}${rects[i].name} ${rects[j].name} ${notation(rel.common)} area ${area(rel.common)}`,
                        );
                }
        }
        output.push(`overlaps ${a ?? "all layers"}: ${found.length}`, ...found);
        return;
    }
    if (["INTERSECT", "ADJACENT", "ENCLOSE", "PATH"].includes(command)) {
        const [first, second] = pair(a, b),
            rel = relation(first, second),
            heading = command.toLowerCase() + " " + a + " " + b + ": ";
        if (command === "INTERSECT")
            output.push(
                heading +
                    (rel.kind === "overlap"
                        ? `${notation(rel.common)} area ${area(rel.common)}`
                        : rel.kind === "edge"
                          ? `segment ${notation(rel.common)} length ${rel.ox + rel.oy}`
                          : rel.kind === "corner"
                            ? "point " + point(rel.common.x1, rel.common.y1)
                            : "none, gap " + rel.gap),
            );
        else if (command === "ADJACENT") {
            const direction =
                rel.ox === 0
                    ? first.x2 === rel.common.x1
                        ? "west"
                        : "east"
                    : first.y2 === rel.common.y1
                      ? "south"
                      : "north";
            output.push(
                heading +
                    (rel.kind === "overlap"
                        ? "overlapping"
                        : rel.kind === "edge"
                          ? `${a} is ${direction} of ${b}, edge ${notation(rel.common)}, length ${rel.ox + rel.oy}`
                          : rel.kind === "corner"
                            ? "corner only at " + point(rel.common.x1, rel.common.y1)
                            : "not adjacent"),
            );
        } else if (command === "ENCLOSE") {
            const values = margins(first, second),
                yes = values.every((value) => value >= 0);
            output.push(
                heading +
                    `${yes ? "yes" : "no"}, margins left ${values[0]} bottom ${values[1]} right ${values[2]} top ${values[3]}${yes ? ", min " + Math.min(...values) : ""}`,
            );
        } else {
            if (first.layer !== second.layer) fail("different layers");
            const rects = onLayer(first.layer),
                queue = [first],
                parents = new Map([[a, null]]);
            for (let i = 0; i < queue.length; i++)
                for (const next of rects)
                    if (!parents.has(next.name) && connected(queue[i], next)) {
                        parents.set(next.name, queue[i].name);
                        queue.push(next);
                    }
            if (!parents.has(b)) output.push(heading + "none");
            else {
                const path = [];
                for (let name = b; name !== null; name = parents.get(name)) path.push(name);
                path.reverse();
                output.push(heading + `${path.join(" -> ")} (${path.length - 1} steps)`);
            }
        }
        return;
    }
    if (command === "AT") {
        const x = Number(a),
            y = Number(b),
            list = ordered()
                .filter((rect) => rect.x1 <= x && x <= rect.x2 && rect.y1 <= y && y <= rect.y2)
                .map((rect) => {
                    const horizontal = x === rect.x1 || x === rect.x2,
                        vertical = y === rect.y1 || y === rect.y2;
                    return `${rect.name} ${rect.layer} ${horizontal && vertical ? "corner" : horizontal || vertical ? "edge" : "inside"}`;
                });
        output.push(`at ${point(x, y)}: ${list.join(", ") || "none"}`);
        return;
    }
    if (command === "NEAREST") {
        const rect = rectangle(a),
            others = onLayer(rect.layer)
                .filter((other) => other.name !== a)
                .sort(
                    (x, y) =>
                        relation(rect, x).gap - relation(rect, y).gap || compare(x.name, y.name),
                );
        output.push(
            `nearest ${a}: ${others.length ? others[0].name + " gap " + relation(rect, others[0]).gap : "none"}`,
        );
        return;
    }
    if (command === "RULE") {
        const kind = a.toLowerCase();
        if (kind === "enclose" && b === args[2]) fail("same layer " + b);
        const rule = {
            kind,
            layer: b,
            outer: kind === "enclose" ? args[2] : "",
            value: Number(args[kind === "enclose" ? 3 : 2]),
        };
        rules.set([kind, rule.layer, rule.outer].join(" "), rule);
        output.push(
            `rule ${kind} ${rule.layer}${kind === "enclose" ? " " + rule.outer : ""} ${rule.value}`,
        );
        return;
    }
    if (command === "CHECK") {
        if (!rules.size) fail("no rules");
        let total = 0;
        for (const rule of [...rules.values()].sort(
            (a, b) =>
                compare(a.kind, b.kind) || compare(a.layer, b.layer) || compare(a.outer, b.outer),
        )) {
            const rects = onLayer(rule.layer, false),
                found = [];
            if (rule.kind === "spacing")
                found.push(...violationLines(violations(rects, rule.value)));
            else if (rule.kind === "width") {
                for (const rect of rects) {
                    const width = Math.min(rect.x2 - rect.x1, rect.y2 - rect.y1);
                    if (width < rule.value) found.push(`${rect.name} width ${width}`);
                }
            } else {
                const outers = onLayer(rule.outer, false);
                for (const rect of rects) {
                    const best = outers.length
                        ? Math.max(...outers.map((outer) => Math.min(...margins(outer, rect))))
                        : null;
                    if (best === null || best < rule.value)
                        found.push(`${rect.name} best margin ${best ?? "none"}`);
                }
            }
            output.push(
                `${rule.kind} ${rule.layer}${rule.kind === "enclose" ? " " + rule.outer : ""} ${rule.value}: ${found.length} violations`,
                ...found,
            );
            total += found.length;
        }
        output.push(`check: ${total} violations in ${rules.size} rules`);
        return;
    }
    const layer = command === "COVER" ? b : a,
        rects = onLayer(layer),
        grid = new Coverage(rects),
        box = bounds(rects);
    if (command === "AREA") output.push(`area ${layer}: ${grid.area()}`);
    else if (command === "COVER") output.push(`cover ${layer} >= ${a}: ${grid.area(Number(a))}`);
    else if (command === "PERIMETER") output.push(`perimeter ${layer}: ${grid.perimeter()}`);
    else if (command === "NETS") {
        const groups = nets(rects);
        output.push(`nets ${layer}: ${groups.length}`);
        groups.forEach((group, i) =>
            output.push(
                `net ${i + 1}: ${group.map((rect) => rect.name).join(" ")} area ${new Coverage(group).area()}`,
            ),
        );
    } else if (command === "DRC") {
        const items = violations(rects, Number(b));
        output.push(
            `drc ${layer} spacing ${b}: ${items.length} violations`,
            ...violationLines(items),
        );
    } else if (command === "BBOX")
        output.push(
            `bbox ${layer}: ${notation(box)} ${box.x2 - box.x1}x${box.y2 - box.y1}, ${rects.length} rectangles, density ${decimal(100 * grid.area(), area(box))}%`,
        );
    else if (command === "DENSITY") {
        const w = Number(b),
            columns = Math.ceil((box.x2 - box.x1) / w),
            rows = Math.ceil((box.y2 - box.y1) / w);
        if (columns > 20 || rows > 20) fail("too many windows");
        const values = Array.from({ length: rows }, (_, j) =>
            Array.from({ length: columns }, (_, i) =>
                grid.window({
                    x1: box.x1 + i * w,
                    y1: box.y1 + j * w,
                    x2: box.x1 + (i + 1) * w,
                    y2: box.y1 + (j + 1) * w,
                }),
            ),
        );
        output.push(`density ${layer} window ${w}: ${columns}x${rows}`);
        for (let j = rows - 1; j >= 0; j--)
            output.push(values[j].map((value) => Math.floor((100 * value) / (w * w))).join(" "));
        let min = [0, 0],
            max = [0, 0];
        for (let j = 0; j < rows; j++)
            for (let i = 0; i < columns; i++) {
                if (values[j][i] < values[min[1]][min[0]]) min = [i, j];
                if (values[j][i] > values[max[1]][max[0]]) max = [i, j];
            }
        for (const [label, at] of [
            ["min", min],
            ["max", max],
        ])
            output.push(
                `${label} ${decimal(100 * values[at[1]][at[0]], w * w)}% at ${point(box.x1 + at[0] * w, box.y1 + at[1] * w)}`,
            );
    } else if (command === "RENDER") {
        const [x1, y1, x2, y2] = args.slice(1).map(Number),
            window = { x1, y1, x2, y2 };
        if (x1 >= x2 || y1 >= y2) fail("invalid window");
        if (x2 - x1 > 60 || y2 - y1 > 40) fail("window too large");
        output.push(`render ${layer} ${notation(window)}`);
        for (let y = y2 - 1; y >= y1; y--) {
            let row = "";
            for (let x = x1; x < x2; x++) {
                const count = rects.filter(
                    (rect) => rect.x1 <= x && x < rect.x2 && rect.y1 <= y && y < rect.y2,
                ).length;
                row += count === 0 ? "." : count >= 10 ? "*" : String(count);
            }
            output.push(row);
        }
    } else if (command === "EMPTY") {
        const empty = grid.empty();
        output.push(
            `empty ${layer}: ${empty === null ? "none" : notation(empty) + " area " + area(empty)}`,
        );
    } else if (command === "HOLES") {
        const holes = grid.holes();
        output.push(`holes ${layer}: ${holes.length}`);
        holes.forEach((hole, i) =>
            output.push(`hole ${i + 1}: area ${hole.area}, bbox ${notation(hole.box)}`),
        );
    } else if (command === "MERGE") {
        const pieces = grid.pieces();
        output.push(`merge ${layer}: ${pieces.length} pieces`, ...pieces.map(notation));
    }
}
const input = fs.readFileSync(0, "utf8").split(/\r?\n/),
    count = Number(input[0]);
for (const line of input.slice(1, count + 1)) {
    try {
        execute(line);
    } catch (error) {
        output.push(error.message);
    }
}
if (output.length) process.stdout.write(output.join("\n") + "\n");
