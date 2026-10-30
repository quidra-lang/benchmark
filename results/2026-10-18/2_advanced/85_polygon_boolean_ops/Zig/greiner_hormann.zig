const std = @import("std");
const r = @import("rational.zig");
const i = @import("intersections.zig");
const rings = @import("rings.zig");
pub const Node = struct { point: r.Point, side: usize, crossing: ?*Crossing = null, entering: bool = false,
     next: *Node = undefined, previous: *Node = undefined, other: ?*Node = null };
pub const Crossing = struct { point: r.Point, first: *Node, second: *Node, visited: bool = false };
const Slot = struct { position: r.Fraction, node: *Node };
const NodeList = []const *Node;
pub const Graph = struct {
    rings: [2]rings.Sequence,
    nodes: [2][]const NodeList,
    initial_inside: [2][]const bool,
    crossings: []const *Crossing,
    n_a: usize,
    n_b: usize,
    pub fn init(first: rings.Sequence, second: rings.Sequence) Graph {
        const sequences = [2]rings.Sequence{ first, second };
        var slots: [2][][]std.ArrayList(Slot) = undefined;
        for (sequences, 0..) |sequence, side| {
            slots[side] = r.alloc([]std.ArrayList(Slot), sequence.len);
            for (sequence, slots[side]) |ring, *edges| {
                edges.* = r.zero(std.ArrayList(Slot), ring.len, .empty);
            }
        }
        for (first, 0..) |ring, first_ring| for (ring, 0..) |a, first_edge| {
            const b = ring[(first_edge + 1) % ring.len];
            for (second, 0..) |other, second_ring| for (other, 0..) |c, second_edge| {
                const d = other[(second_edge + 1) % other.len];
                if (i.crossing(a, b, c, d)) |found| {
                    const first_node = r.create(Node, .{ .point = found.point, .side = 0 });
                    const second_node = r.create(Node, .{ .point = found.point, .side = 1 });
                    const record = r.create(Crossing, .{ .point = found.point, .first = first_node,
                         .second = second_node });
                    first_node.crossing = record;
                    second_node.crossing = record;
                    first_node.other = second_node;
                    second_node.other = first_node;
                    r.append(Slot, &slots[0][first_ring][first_edge], .{ .position = found.first, .node = first_node });
                    r.append(Slot, &slots[1][second_ring][second_edge], .{ .position = found.second,
                         .node = second_node });
                }
            };
        };
        var node_rings: [2][]NodeList = undefined;
        var initial: [2][]bool = undefined;
        var ordered: std.ArrayList(*Crossing) = .empty;
        var counts: [2]usize = @splat(0);
        for (sequences, 0..) |sequence, side| {
            node_rings[side] = r.alloc(NodeList, sequence.len);
            initial[side] = r.alloc(bool, sequence.len);
            for (sequence, 0..) |ring, index| {
                var nodes: std.ArrayList(*Node) = .empty;
                for (ring, 0..) |point, edge| {
                    r.append(*Node, &nodes, r.create(Node, .{ .point = point, .side = side }));
                    const inserted = slots[side][index][edge].items;
                    std.mem.sort(Slot, inserted, {}, struct {
                        fn less(_: void, a: Slot, b: Slot) bool {
                            return a.position.less(b.position);
                        }
                    }.less);
                    for (inserted) |slot| r.append(*Node, &nodes, slot.node);
                }
                for (nodes.items, 0..) |node, j| {
                    node.previous = nodes.items[(j + nodes.items.len - 1) % nodes.items.len];
                    node.next = nodes.items[(j + 1) % nodes.items.len];
                }
                var state = rings.interior(sequences[1 - side], ring[0]);
                initial[side][index] = state;
                counts[side] += @intFromBool(state);
                for (nodes.items) |node| if (node.crossing) |record| {
                    node.entering = !state;
                    state = !state;
                    if (side == 0) r.append(*Crossing, &ordered, record);
                };
                node_rings[side][index] = nodes.items;
            }
        }
        return .{ .rings = sequences, .nodes = .{ node_rings[0], node_rings[1] }, .initial_inside = .{ initial[0],
             initial[1] }, .crossings = ordered.items, .n_a = counts[0], .n_b = counts[1] };
    }
    pub fn traverse(self: Graph, invert_first: bool, invert_second: bool) rings.Sequence {
        const inverted = [2]bool{ invert_first, invert_second };
        for (self.crossings) |record| record.visited = false;
        var result: std.ArrayList(rings.Ring) = .empty;
        for (self.crossings) |start| {
            if (start.visited) continue;
            var points: std.ArrayList(r.Point) = .empty;
            var current = start.first;
            while (true) {
                current.crossing.?.visited = true;
                r.append(r.Point, &points, current.point);
                const forward = current.entering != inverted[current.side];
                var stopped = if (forward) current.next else current.previous;
                while (stopped.crossing == null) {
                    r.append(r.Point, &points, stopped.point);
                    stopped = if (forward) stopped.next else stopped.previous;
                }
                if (stopped.crossing.? == start) break;
                current = stopped.other.?;
            }
            r.append(rings.Ring, &result, points.items);
        }
        for (self.rings, 0..) |sequence, side| for (sequence, 0..) |ring, index| {
            var crossed = false;
            for (self.nodes[side][index]) |node| crossed = crossed or node.crossing != null;
            if (!crossed and self.initial_inside[side][index] != inverted[side]) r.append(rings.Ring, &result, ring);
        };
        return result.items;
    }
};
