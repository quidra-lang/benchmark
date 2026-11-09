const std = @import("std");
const g = @import("graph_io.zig");
pub const Orders = [][]usize;
pub fn clone(a: Orders) Orders { const out = g.alloc([]usize, a.len); for (a, out) |row, *dest| dest.* = g.copy(usize, row); return out; }
pub fn positions(orders: Orders, n: usize) []usize { const pos = g.alloc(usize, n); for (orders) |row| for (row, 0..) |v,i| { pos[v] = i; }; return pos; }
pub fn same(a: Orders, b: Orders) bool { for (a,b) |x,y| if (!std.mem.eql(usize,x,y)) return false; return true; }
pub fn crosses(a: g.Segment, b: g.Segment, pos: []const usize) bool { return (pos[a.upper] < pos[b.upper] and pos[a.lower] > pos[b.lower]) or (pos[a.upper] > pos[b.upper] and pos[a.lower] < pos[b.lower]); }
pub fn gap(graph: *const g.Graph, orders: Orders, layer: usize) usize {
    const pos = positions(orders, graph.vertices.items.len); const Pair = struct { a: usize, b: usize }; var pairs: std.ArrayList(Pair) = .empty;
    for (graph.segments.items) |s| if (graph.vertices.items[s.upper].layer == layer) g.append(Pair,&pairs,.{ .a=pos[s.upper], .b=pos[s.lower] });
    std.mem.sort(Pair,pairs.items,{},struct { fn less(_:void,a:Pair,b:Pair) bool { return a.a < b.a or (a.a == b.a and a.b < b.b); } }.less);
    var c: usize = 1; while (c < orders[layer + 1].len) c *= 2; const tree = g.zero(usize,2*c-1,0); var count: usize = 0;
    for (pairs.items) |pair| { var k = pair.b + c - 1; tree[k] += 1; while (k > 0) { if (k % 2 == 1) count += tree[k + 1]; k = (k - 1) / 2; tree[k] += 1; } } return count;
}
pub fn total(graph: *const g.Graph, orders: Orders) usize { var count: usize = 0; for (0..orders.len-1) |i| count += gap(graph,orders,i); return count; }
pub fn brute(graph: *const g.Graph, orders: Orders) usize { const pos=positions(orders,graph.vertices.items.len); var count:usize=0; for(graph.segments.items,0..) |a,i| for(graph.segments.items[i+1..]) |b| { if(graph.vertices.items[a.upper].layer == graph.vertices.items[b.upper].layer and crosses(a,b,pos)) count+=1; }; return count; }
pub fn neighbors(graph: *const g.Graph, vertex:usize, upper:bool) []usize { var out:std.ArrayList(usize)=.empty; for(graph.segments.items) |s| { if(upper and s.lower==vertex) g.append(usize,&out,s.upper); if(!upper and s.upper==vertex) g.append(usize,&out,s.lower); } return out.items; }
pub fn cost(graph:*const g.Graph, v:usize,w:usize,pos:[]const usize) usize { var count:usize=0; for([_]bool{true,false}) |up| for(neighbors(graph,v,up)) |a| for(neighbors(graph,w,up)) |b| { count+=@intFromBool(pos[a]>pos[b]); }; return count; }
