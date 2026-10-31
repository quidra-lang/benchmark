const std = @import("std");
const h = @import("headers.zig");
const addresses = @import("addresses.zig");

pub const Message = struct {
    number: usize,
    thread: usize = 0,
    depth: usize = 0,
    sender: ?addresses.Mailbox = null,
    to: h.Strings = &.{},
    cc: h.Strings = &.{},
    subject: []const u8 = "",
    base_subject: []const u8 = "",
    reply: bool = false,
    date: ?i64 = null,
    id: []const u8 = "",
    references: h.Strings = &.{},
    body: *h.Entity = undefined,
    problems: h.Lines = .{},
    parent: ?*Message = null,
};

pub const Container = struct {
    id: []const u8,
    subject: ?[]const u8 = null,
    message: ?*Message = null,
    parent: ?*Container = null,
    children: std.ArrayList(*Container) = .empty,
};

fn newContainer(id: []const u8) *Container {
    const container = &h.alloc(Container, 1)[0];
    container.* = .{ .id = id };
    return container;
}

fn containerOf(all: *std.ArrayList(*Container), id: []const u8) *Container {
    for (all.items) |container| if (container.id.len > 0 and h.eq(container.id, id)) return container;
    const container = newContainer(id);
    h.append(*Container, all, container);
    return container;
}

fn ancestor(first: *Container, second: *Container) bool {
    var current: ?*Container = second;
    while (current) |container| {
        if (first == container) return true;
        current = container.parent;
    }
    return false;
}

fn adopt(parent: *Container, child: *Container) void {
    child.parent = parent;
    h.append(*Container, &parent.children, child);
}

fn prune(containers: []*Container, at_root: bool) std.ArrayList(*Container) {
    var result: std.ArrayList(*Container) = .empty;
    for (containers) |container| {
        container.children = prune(container.children.items, false);
        if (container.message != null or (at_root and container.children.items.len >= 2)) {
            h.append(*Container, &result, container);
        } else {
            for (container.children.items) |child| {
                child.parent = if (at_root) null else container.parent;
                h.append(*Container, &result, child);
            }
        }
    }
    return result;
}

pub fn compareMessages(first: *const Message, second: *const Message) std.math.Order {
    if ((first.date != null) != (second.date != null)) return if (first.date != null) .lt else .gt;
    if (first.date) |value| if (value != second.date.?) return std.math.order(value, second.date.?);
    const id_order = std.mem.order(u8, first.id, second.id);
    return if (id_order != .eq) id_order else std.math.order(first.number, second.number);
}

fn key(container: *Container) *Message {
    if (container.message) |message| return message;
    var minimum: ?*Message = null;
    for (container.children.items) |child| {
        const candidate = key(child);
        if (minimum == null or compareMessages(candidate, minimum.?) == .lt) minimum = candidate;
    }
    return minimum.?;
}

fn lessThan(_: void, first: *Container, second: *Container) bool {
    return compareMessages(key(first), key(second)) == .lt;
}

fn sortContainers(containers: []*Container) void {
    for (containers) |container| sortContainers(container.children.items);
    std.mem.sort(*Container, containers, {}, lessThan);
}

pub fn rootSubject(root: *Container) []const u8 {
    return if (root.message) |message| message.base_subject else root.children.items[0].message.?.base_subject;
}

fn mergeSubjects(roots: []*Container) []*Container {
    var result: std.ArrayList(*Container) = .empty;
    const handled = h.alloc(bool, roots.len);
    @memset(handled, false);
    for (roots, 0..) |root, i| {
        if (handled[i]) continue;
        const subject = rootSubject(root);
        var group: std.ArrayList(*Container) = .empty;
        for (roots[i..], i..) |candidate, j| {
            if (j == i or (subject.len > 0 and h.eq(subject, rootSubject(candidate)))) {
                handled[j] = true;
                h.append(*Container, &group, candidate);
            }
        }
        if (group.items.len == 1) {
            h.append(*Container, &result, group.items[0]);
            continue;
        }
        var target: ?*Container = null;
        var original: ?*Container = null;
        var originals: usize = 0;
        for (group.items) |container| {
            if (container.message) |message| {
                if (!message.reply) { original = container; originals += 1; }
            } else if (target == null) target = container;
        }
        if (target == null and originals == 1) target = original;
        if (target == null) {
            target = newContainer("");
            target.?.subject = subject;
        }
        for (group.items) |container| {
            if (container == target.?) continue;
            if (container.message != null) adopt(target.?, container) else {
                for (container.children.items) |child| adopt(target.?, child);
            }
        }
        h.append(*Container, &result, target.?);
    }
    return result.items;
}

pub fn build(messages: []Message) []*Container {
    var all: std.ArrayList(*Container) = .empty;
    for (messages) |*message| {
        const container = if (message.id.len > 0) containerOf(&all, message.id) else blk: {
            const anonymous = newContainer("");
            h.append(*Container, &all, anonymous);
            break :blk anonymous;
        };
        container.message = message;
        const references = h.alloc(*Container, message.references.len);
        for (message.references, references) |id, *reference| reference.* = containerOf(&all, id);
        if (references.len > 0) {
            for (references[0 .. references.len - 1], references[1..]) |first, second| {
                if (second.parent == null and !ancestor(second, first)) adopt(first, second);
            }
        }
        if (container.parent) |parent| {
            for (parent.children.items, 0..) |sibling, i| {
                if (sibling == container) { _ = parent.children.orderedRemove(i); break; }
            }
            container.parent = null;
        }
        if (references.len > 0 and !ancestor(container, references[references.len - 1])) adopt(references[references.len - 1], container);
    }
    var roots: std.ArrayList(*Container) = .empty;
    for (all.items) |container| if (container.parent == null) h.append(*Container, &roots, container);
    roots = prune(roots.items, true);
    sortContainers(roots.items);
    const merged = mergeSubjects(roots.items);
    sortContainers(merged);
    return merged;
}
