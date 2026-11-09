const std=@import("std");
const p=@import("pddl_parser.zig");
const g=@import("grounding.zig");
const h=@import("heuristics.zig");
pub const Run=struct { algorithm:[]const u8,heuristic:[]const u8,pub fn tag(self:Run) []const u8 { return p.fmt("{s} {s}",.{self.algorithm,self.heuristic}); } };
pub const Result=struct { status:[]const u8="exhausted",plan:[]const usize=&.{},expanded:usize=0,generated:usize=0 };
pub fn applicable(action:g.Action,state:g.Set) bool { return g.subset(action.pre,state) and action.neg&state==0; }
pub fn apply(action:g.Action,state:g.Set) g.Set { return (state&~action.del)|action.add; }
pub fn cost(ground:g.Ground,plan:[]const usize) i64 { var total:i64=0; for(plan) |a| total+=ground.actions[a].cost; return total; }
const Node=struct { state:g.Set,g:i64,depth:i64,h:i64,serial:usize,parent:?*Node=null,action:usize=0 };
fn rebuildPlan(node:*Node) []const usize { var out:std.ArrayList(usize)=.empty; var at=node; while(at.parent) |parent| { p.append(usize,&out,at.action); at=parent; } std.mem.reverse(usize,out.items); return out.items; }
fn f(node:*const Node,algorithm:[]const u8,weight:i64) i64 { if(p.eq(algorithm,"bfs")) return node.depth; if(p.eq(algorithm,"ucs")) return node.g; if(p.eq(algorithm,"gbfs")) return node.h; return node.g+(if(p.eq(algorithm,"wastar")) weight else @as(i64,1))*node.h; }
fn before(a:*const Node,b:*const Node,algorithm:[]const u8,weight:i64) bool { const x=f(a,algorithm,weight); const y=f(b,algorithm,weight); return x<y or (x==y and (a.h<b.h or (a.h==b.h and a.serial<b.serial))); }
pub fn run(ground:g.Ground,start:g.Set,settings:Run,budget:usize,weight:i64) Result {
    if(p.eq(settings.algorithm,"ehc")) return hill(ground,start,settings.heuristic,budget);
    var out:Result=.{}; const start_h=h.estimate(ground,start,settings.heuristic); if(start_h>=h.infinity) { out.status="dead end"; return out; }
    var table=std.AutoHashMap(g.Set,i64).init(p.allocator); table.put(start,0) catch @panic("allocation failed"); var open:std.ArrayList(*Node)=.empty; var serial:usize=1; p.append(*Node,&open,p.create(Node,.{.state=start,.g=0,.depth=0,.h=start_h,.serial=0})); const weighted=!p.eq(settings.algorithm,"bfs") and !p.eq(settings.algorithm,"gbfs");
    while(open.items.len>0) {
        var best:usize=0; for(open.items,0..) |node,i| if(before(node,open.items[best],settings.algorithm,weight)) { best=i; }; const node=open.orderedRemove(best);
        if(weighted and node.g>table.get(node.state).?) continue;
        if(g.subset(ground.goal,node.state)) { out.status="solved"; out.plan=rebuildPlan(node); return out; }
        if(out.expanded==budget) { out.status="budget"; return out; } out.expanded+=1;
        for(ground.actions,0..) |action,a| { if(!applicable(action,node.state)) continue; out.generated+=1; const state=apply(action,node.state); const distance=node.g+action.cost;
            if(table.get(state)) |old| { if(!weighted or old<=distance) continue; } table.put(state,distance) catch @panic("allocation failed"); const heuristic=h.estimate(ground,state,settings.heuristic); if(heuristic>=h.infinity) continue;
            p.append(*Node,&open,p.create(Node,.{.state=state,.g=distance,.depth=node.depth+1,.h=heuristic,.serial=serial,.parent=node,.action=a})); serial+=1;
        }
    }
    return out;
}
fn hill(ground:g.Ground,start:g.Set,heuristic:[]const u8,budget:usize) Result {
    var out:Result=.{}; var state=start; var current=h.estimate(ground,state,heuristic); var solution:std.ArrayList(usize)=.empty; if(current>=h.infinity) { out.status="dead end"; return out; }
    outer: while(true) {
        if(g.subset(ground.goal,state)) { out.status="solved"; out.plan=solution.items; return out; }
        var visited=std.AutoHashMap(g.Set,void).init(p.allocator); visited.put(state,{}) catch @panic("allocation failed"); var queue:std.ArrayList(*Node)=.empty; p.append(*Node,&queue,p.create(Node,.{.state=state,.g=0,.depth=0,.h=current,.serial=0})); var at:usize=0;
        while(at<queue.items.len) : (at+=1) {
            const node=queue.items[at]; if(out.expanded==budget) { out.status="budget"; return out; } out.expanded+=1;
            for(h.helpfulActions(ground,node.state)) |a| { const next=apply(ground.actions[a],node.state); out.generated+=1; if(visited.contains(next)) continue; visited.put(next,{}) catch @panic("allocation failed"); const value=h.estimate(ground,next,heuristic); if(value>=h.infinity) continue; const child=p.create(Node,.{.state=next,.g=0,.depth=node.depth+1,.h=value,.serial=0,.parent=node,.action=a});
                if(value<current) { for(rebuildPlan(child)) |step| p.append(usize,&solution,step); state=next; current=value; continue :outer; } p.append(*Node,&queue,child);
            }
        }
        out.status="stuck"; return out;
    }
}
