const std = @import("std");
const c = @import("dataframe.zig");
pub const Factor = struct { name: []const u8, column: usize, power: usize = 1, categorical: bool = false };
pub const Term = struct { factors: []const Factor, name: []const u8 };
pub const Formula = struct { response: usize, weight: ?usize = null, raw: []const u8, terms: []const Term };
pub const Component = struct { name: []const u8, label: []const u8 = "", column: usize, power: usize = 1,
     categorical: bool = false };
pub const Column = struct { name: []const u8, term: ?usize = null, components: []const Component = &.{} };
pub const LevelList = []const []const u8;
pub const Design = struct { formula: Formula, used: []const usize, levels: []LevelList, columns: []const Column,
     x: c.Matrix, y: c.Vector, weights: c.Vector };
fn split(text: []const u8, delimiter: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitSequence(u8, text, delimiter);
    while (iterator.next()) |field| c.append([]const u8, &out, field);
    return out.items;
}
fn factor(name: []const u8, data: c.Dataframe) Factor {
    var column = name;
    var power: usize = 1;
    var categorical = false;
    if (std.mem.startsWith(u8, name, "C(")) {
        categorical = true;
        column = name[2 .. name.len - 1];
    } else if (std.mem.startsWith(u8, name, "I(")) {
        const caret = std.mem.indexOfScalar(u8, name, '^').?;
        column = name[2..caret];
        power = c.u(c.number(name[caret + 1 .. name.len - 1]));
    }
    return .{ .name = name, .column = c.nameIndex(data.names, column), .power = power, .categorical = categorical };
}
fn member(term: Term, name: []const u8) bool {
    for (term.factors) |value| if (c.eq(value.name, name)) return true;
    return false;
}
fn sameTerm(a: Term, b: Term) bool {
    if (a.factors.len != b.factors.len) return false;
    for (a.factors) |value| if (!member(b, value.name)) return false;
    return true;
}
pub fn parse(line: []const u8, data: c.Dataframe) Formula {
    const weight_position = std.mem.indexOf(u8, line, " weights=");
    const raw = if (weight_position) |position| line[0..position] else line;
    const weight = if (weight_position) |position| c.nameIndex(data.names, line[position + 9 ..]) else null;
    const sides = split(raw, " ~ ");
    var terms: std.ArrayList(Term) = .empty;
    for (split(sides[1], " + ")) |expression| {
        const star = std.mem.indexOfScalar(u8, expression, '*') != null;
        const names_ = split(expression, if (star) "*" else ":");
        for (1..names_.len + 1) |count| for (1..@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(names_.len))) |mask| {
            if ((star and @popCount(mask) != count) or (!star and (count != names_.len or mask != (@as(usize,
                 1) << @as(std.math.Log2Int(usize), @intCast(names_.len))) - 1))) continue;
            var factors: std.ArrayList(Factor) = .empty;
            var name: c.Text = .{};
            for (names_, 0..) |factor_name, j| if ((mask & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(j)))) != 0) {
                c.append(Factor, &factors, factor(factor_name, data));
                name.add("{s}{s}", .{ if (name.value().len == 0) "" else ":", factor_name });
            };
            const term: Term = .{ .factors = factors.items, .name = name.value() };
            var duplicate = false;
            for (terms.items) |earlier| if (sameTerm(earlier, term)) {
                duplicate = true;
            };
            if (!duplicate) c.append(Term, &terms, term);
        };
    }
    return .{ .response = c.nameIndex(data.names, sides[0]), .weight = weight, .raw = raw, .terms = terms.items };
}
pub fn contained(a: Term, b: Term) bool {
    if (a.factors.len >= b.factors.len) return false;
    for (a.factors) |value| if (!member(b, value.name)) return false;
    return true;
}
pub fn text(formula: Formula, terms: []const usize, data: c.Dataframe) []const u8 {
    var out: c.Text = .{};
    out.add("{s} ~ ", .{data.names[formula.response]});
    if (terms.len == 0) out.add("1", .{}) else for (terms, 0..) |term, i| {
        out.add("{s}{s}", .{ if (i == 0) "" else " + ", formula.terms[term].name });
    };
    return out.value();
}
pub fn recordValues(columns: []const Column, record: c.Record) c.Vector {
    const out = c.vector(columns.len);
    for (columns, out) |column, *value| {
        value.* = 1;
        for (column.components) |component| {
            var part = if (component.categorical) @as(f64, if (c.eq(record[component.column].?.label,
                 component.label)) 1 else 0) else record[component.column].?.number;
            if (!component.categorical) {
                if (component.power == 2) part = part * part else if (component.power == 3) part = part * part * part;
            }
            value.* = value.* * part;
        }
    }
    return out;
}
fn textLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
pub fn build(formula: Formula, data: c.Dataframe) Design {
    const variables = c.alloc(bool, data.names.len);
    @memset(variables, false);
    variables[formula.response] = true;
    if (formula.weight) |column| variables[column] = true;
    for (formula.terms) |term| for (term.factors) |value| {
        variables[value.column] = true;
    };
    var used: std.ArrayList(usize) = .empty;
    for (data.rows, 0..) |record, i| {
        var complete = true;
        for (record, variables) |value, required| if (required and value == null) {
            complete = false;
        };
        if (complete) c.append(usize, &used, i);
    }
    const levels = c.alloc(LevelList, data.names.len);
    @memset(levels, &.{});
    for (formula.terms) |term| for (term.factors) |value| {
        if (!value.categorical or levels[value.column].len > 0) continue;
        var labels: std.ArrayList([]const u8) = .empty;
        for (used.items) |row| {
            const label = data.rows[row][value.column].?.label;
            var found = false;
            for (labels.items) |earlier| if (c.eq(earlier, label)) {
                found = true;
            };
            if (!found) c.append([]const u8, &labels, label);
        }
        std.mem.sort([]const u8, labels.items, {}, textLess);
        levels[value.column] = labels.items;
    };
    var columns: std.ArrayList(Column) = .empty;
    c.append(Column, &columns, .{ .name = "(Intercept)" });
    for (formula.terms, 0..) |term, t| {
        var parts: std.ArrayList([]const Component) = .empty;
        var count: usize = 1;
        for (term.factors) |value| {
            var components: std.ArrayList(Component) = .empty;
            if (value.categorical) {
                for (levels[value.column][1..]) |label| c.append(Component, &components, .{ .name = c.fmt("{s}{s}",
                     .{ value.name, label }), .label = label, .column = value.column, .categorical = true });
            } else c.append(Component, &components, .{ .name = value.name, .column = value.column, .power = value.power });
            count *= components.items.len;
            c.append([]const Component, &parts, components.items);
        }
        for (0..count) |index| {
            var remainder = index;
            var components: std.ArrayList(Component) = .empty;
            var name: c.Text = .{};
            for (parts.items) |choices| {
                const component = choices[remainder % choices.len];
                remainder /= choices.len;
                c.append(Component, &components, component);
                name.add("{s}{s}", .{ if (name.value().len == 0) "" else ":", component.name });
            }
            c.append(Column, &columns, .{ .name = name.value(), .term = t, .components = components.items });
        }
    }
    const x = c.alloc(c.Vector, used.items.len);
    const y = c.vector(used.items.len);
    const weights = c.vector(used.items.len);
    for (used.items, x, y, weights) |row, *values, *response, *weight| {
        values.* = recordValues(columns.items, data.rows[row]);
        response.* = data.rows[row][formula.response].?.number;
        weight.* = if (formula.weight) |column| data.rows[row][column].?.number else 1;
    }
    return .{ .formula = formula, .used = used.items, .levels = levels, .columns = columns.items,
         .x = x, .y = y, .weights = weights };
}
pub fn selectedColumns(design: Design, terms: []const usize) []const usize {
    var out: std.ArrayList(usize) = .empty;
    c.append(usize, &out, 0);
    for (design.columns[1..], 1..) |column, j| if (std.mem.indexOfScalar(usize, terms, column.term.?) != null) c.append(usize,
         &out, j);
    return out.items;
}
pub fn predictable(design: Design, record: c.Record) bool {
    for (design.formula.terms) |term| for (term.factors) |value| {
        if (record[value.column] == null) return false;
        if (value.categorical) {
            const label = record[value.column].?.label;
            var found = false;
            for (design.levels[value.column]) |level| if (c.eq(level, label)) {
                found = true;
            };
            if (!found) return false;
        }
    };
    return true;
}
