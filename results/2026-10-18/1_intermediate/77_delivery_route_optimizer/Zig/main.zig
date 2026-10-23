const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";
fn equal(a: Text, b: Text) bool { return std.mem.eql(u8,a,b); }
fn number(s: Text) Int { return std.fmt.parseInt(Int,s,10) catch unreachable; }
fn natural(s: Text) usize { return @intCast(number(s)); }
fn abs(n: Int) Int { return if(n<0) -n else n; }
fn clock(s: Text) Int { return number(s[0..2])*60+number(s[3..]); }
fn timeText(gpa: Allocator,t: Int) Allocator.Error!Text { return std.fmt.allocPrint(gpa,"{d:0>2}:{d:0>2}",.{@divTrunc(t,60),@mod(t,60)}); }
fn label(gpa: Allocator,id: usize) Allocator.Error!Text { return if(id==0) "D" else std.fmt.allocPrint(gpa,"{d}",.{id}); }
const Builder = struct {
    gpa: Allocator, bytes: std.ArrayList(u8)=.empty,
    fn add(self: *Builder,s: Text) Allocator.Error!void { try self.bytes.appendSlice(self.gpa,s); }
    fn print(self: *Builder,comptime format: Text,args: anytype) Allocator.Error!void { try self.add(try std.fmt.allocPrint(self.gpa,format,args)); }
    fn line(self: *Builder,comptime format: Text,args: anytype) Allocator.Error!void { try self.print(format++"\n",args); }
};
fn words(gpa: Allocator,s: Text) Allocator.Error![]Text {
    var list: std.ArrayList(Text)=.empty; var iterator=std.mem.tokenizeScalar(u8,s,' ');
    while(iterator.next()) |word| try list.append(gpa,word); return list.items;
}
fn intLess(_: void,a: usize,b: usize) bool { return a<b; }
fn reverse(p: []usize) void { std.mem.reverse(usize,p); }
fn concatenate(gpa: Allocator,a: []const usize,b: []const usize) Allocator.Error![]usize {
    const result=try gpa.alloc(usize,a.len+b.len); @memcpy(result[0..a.len],a); @memcpy(result[a.len..],b); return result;
}
fn place(gpa: Allocator,p: []const usize,index: usize,values: []const usize) Allocator.Error![]usize {
    const result=try gpa.alloc(usize,p.len+values.len);
    @memcpy(result[0..index],p[0..index]);
    @memcpy(result[index..index+values.len],values);
    @memcpy(result[index+values.len..],p[index..]);
    return result;
}
fn notation(gpa: Allocator,p: []const usize) Allocator.Error!Text {
    var out: Builder=.{.gpa=gpa}; try out.add("D"); for(p) |id| try out.print("-{d}",.{id}); try out.add("-D"); return out.bytes.items;
}
fn minimum(p: []const usize) usize { var value=p[0]; for(p) |id| value=@min(value,id); return value; }
fn routeLess(_: void,a: []usize,b: []usize) bool { return minimum(a)<minimum(b); }
fn at(p: []const usize,index: usize) usize { return if(index==0 or index>p.len) 0 else p[index-1]; }
const Stop = struct { x: Int=0, y: Int=0, demand: Int=0, service: Int=0, open: ?Int=null, close: Int=0 };
const Run = struct { returned: Int=0, travel: Int=0, wait: Int=0, service: Int=0, violations: Int=0, lateness: Int=0 };
const Workbench = struct {
    gpa: Allocator, out: *Builder,
    depot: ?Stop=null, start: Int=480,
    stops: std.AutoHashMapUnmanaged(usize,Stop)=.empty,
    tour: ?[]usize=null,
    routes: ?std.ArrayList([]usize)=null,
    capacity: Int=0,
    fn fail(self: *Workbench,comptime format: Text,args: anytype) Error {
        failure=std.fmt.allocPrint(self.gpa,"error: "++format,args) catch return error.OutOfMemory; return error.Invalid;
    }
    fn ids(self: *Workbench) Error![]usize {
        var result: std.ArrayList(usize)=.empty; var iterator=self.stops.keyIterator(); while(iterator.next()) |id| try result.append(self.gpa,id.*);
        std.mem.sort(usize,result.items,{},intLess); return result.items;
    }
    fn distance(self: *Workbench,a: usize,b: usize) Int {
        const p=if(a==0) self.depot.? else self.stops.get(a).?; const q=if(b==0) self.depot.? else self.stops.get(b).?;
        return abs(p.x-q.x)+abs(p.y-q.y);
    }
    fn length(self: *Workbench,p: []const usize) Int {
        var total: Int=0; var last: usize=0; for(p) |id| { total+=self.distance(last,id); last=id; } return total+self.distance(last,0);
    }
    fn load(self: *Workbench,p: []const usize) Int { var total: Int=0; for(p) |id| total+=self.stops.get(id).?.demand; return total; }
    fn total(self: *Workbench) Int { var result: Int=0; for(self.routes.?.items) |p| result+=self.length(p); return result; }
    fn normalize(self: *Workbench) Error!void {
        var result: std.ArrayList([]usize)=.empty;
        for(self.routes.?.items) |p| { if(p.len==0) continue; if(p[0]>p[p.len-1]) reverse(p); try result.append(self.gpa,p); }
        std.mem.sort([]usize,result.items,{},routeLess); self.routes=result;
    }
    fn routeLines(self: *Workbench) Error!void { for(self.routes.?.items,0..) |p,i| try self.out.line("route {d}: {s} load {d} length {d}",.{i+1,try notation(self.gpa,p),self.load(p),self.length(p)}); }
    fn simulate(self: *Workbench,p: []const usize,display: bool) Error!Run {
        var result: Run=.{.travel=self.length(p)}; var t=self.start; var last: usize=0;
        for(p) |id| {
            const item=self.stops.get(id).?; const arrival=t+self.distance(last,id);
            const wait=if(item.open) |open| @max(0,open-arrival) else 0; const late=if(item.open!=null) @max(0,arrival-item.close) else 0;
            const begin=arrival+wait; t=begin+item.service; last=id; result.wait+=wait; result.service+=item.service; result.lateness+=late; if(late>0) result.violations+=1;
            if(display) try self.out.line("{d} arrive {s} wait {d} begin {s} leave {s} {s}",.{id,try timeText(self.gpa,arrival),wait,try timeText(self.gpa,begin),try timeText(self.gpa,t),if(late>0) try std.fmt.allocPrint(self.gpa,"late {d}",.{late}) else "ok"});
        }
        result.returned=t+self.distance(last,0);
        if(display) try self.out.line("return {s}, travel {d}, wait {d}, service {d}, violations {d}, lateness {d}",.{try timeText(self.gpa,result.returned),result.travel,result.wait,result.service,result.violations,result.lateness});
        return result;
    }
    fn twoopt(self: *Workbench,p: []usize,display: bool) Error!usize {
        var moves: usize=0;
        while(true) {
            var changed=false;
            scan: for(0..p.len) |i| { for(i+1..p.len) |j| {
                const a=at(p,i); const b=at(p,j+2);
                const gain=self.distance(a,p[i])+self.distance(p[j],b)-self.distance(a,p[j])-self.distance(p[i],b);
                if(gain>0) { if(display) try self.out.line("reverse {d}..{d} gain {d}",.{p[i],p[j],gain}); reverse(p[i..j+1]); moves+=1; changed=true; break :scan; }
            } }
            if(!changed) return moves;
        }
    }
    fn baseCheck(self: *Workbench) Error!void { if(self.depot==null) return self.fail("no depot",.{}); if(self.stops.count()==0) return self.fail("no stops",.{}); }
    fn capacityCheck(self: *Workbench,q: Int) Error!void {
        for(try self.ids()) |id| if(self.stops.get(id).?.demand>q) return self.fail("stop {d} demand {d} exceeds capacity {d}",.{id,self.stops.get(id).?.demand,q});
    }
    fn exact(self: *Workbench) Error![]usize {
        const list=try self.ids(); var search: Exact=.{.w=self,.ids=list}; const full=(@as(usize,1)<<@intCast(list.len))-1;
        var mask=full; var last: usize=0; var result: std.ArrayList(usize)=.empty;
        while(mask!=0) { const best=try search.cost(mask,last); for(list,0..) |id,i| { const bit=@as(usize,1)<<@intCast(i); if(mask&bit!=0 and self.distance(last,id)+try search.cost(mask^bit,id)==best) { try result.append(self.gpa,id); mask^=bit; last=id; break; } } }
        return result.items;
    }
    fn bound(self: *Workbench) Error!void {
        const list=try self.ids(); var tree: std.ArrayList(usize)=.empty; try tree.append(self.gpa,0); var used: std.AutoHashMapUnmanaged(usize,void)=.empty;
        var edges: Builder=.{.gpa=self.gpa}; var mst: Int=0;
        for(0..list.len) |round| {
            var best: Int=std.math.maxInt(Int); var candidate: usize=0; var parent: usize=0;
            for(list) |id| { if(used.contains(id)) continue; for(tree.items) |p| { const d=self.distance(p,id); if(d<best) { best=d; candidate=id; parent=p; } } }
            if(round>0) try edges.add(" "); try edges.print("{s}-{d}",.{try label(self.gpa,parent),candidate}); mst+=best; try used.put(self.gpa,candidate,{}); try tree.append(self.gpa,candidate);
        }
        var one=2*self.distance(0,list[0]);
        if(list.len>1) {
            const distances=try self.gpa.alloc(Int,list.len); for(list,0..) |id,i| distances[i]=self.distance(0,id);
            std.mem.sort(Int,distances,{},struct { fn less(_: void,a: Int,b: Int) bool { return a<b; } }.less); one=distances[0]+distances[1];
            used=.empty; try used.put(self.gpa,list[0],{});
            while(used.count()<list.len) {
                var best: Int=std.math.maxInt(Int); var candidate: usize=0;
                for(list) |a| { if(!used.contains(a)) continue; for(list) |b| { if(!used.contains(b) and self.distance(a,b)<best) { best=self.distance(a,b); candidate=b; } } }
                one+=best; try used.put(self.gpa,candidate,{});
            }
        }
        const best=@max(mst,one); try self.out.line("mst: {s} (length {d})",.{edges.bytes.items,mst}); try self.out.line("bound: mst {d}, one-tree {d}, best {d}",.{mst,one,best});
        if(self.tour) |p| { const lengthValue=self.length(p); const u=if(best>0) @divTrunc(2000*(lengthValue-best)+best,2*best) else 0; try self.out.line("gap: tour {d}, {d}.{d}%",.{lengthValue,@divTrunc(u,10),@mod(u,10)}); }
        else try self.out.line("gap: no tour",.{});
    }
    fn improve(self: *Workbench,command: Text) Error!void {
        const initial=self.total(); const k0=self.routes.?.items.len; var moves: usize=0;
        while(true) {
            var changed=false;
            if(equal(command,"RELOCATE")) {
                scan: for(self.routes.?.items,0..) |a,r| { for(a,0..) |c,p| { for(self.routes.?.items,0..) |b,t| {
                    if(r==t or self.load(b)+self.stops.get(c).?.demand>self.capacity) continue;
                    for(0..b.len+1) |j| {
                        const before=at(a,p); const after=at(a,p+2); const u=at(b,j); const v=at(b,j+1);
                        const gain=self.distance(before,c)+self.distance(c,after)-self.distance(before,after)-self.distance(u,c)-self.distance(c,v)+self.distance(u,v);
                        if(gain>0) {
                            try self.out.line("relocate {d} from route {d} to route {d} after {s} gain {d}",.{c,r+1,t+1,try label(self.gpa,u),gain});
                            self.routes.?.items[r]=try concatenate(self.gpa,a[0..p],a[p+1..]); self.routes.?.items[t]=try place(self.gpa,b,j,&.{c}); changed=true; break :scan;
                        }
                    }
                } } }
            } else if(equal(command,"EXCHANGE")) {
                scan: for(self.routes.?.items,0..) |a,r| { for(r+1..self.routes.?.items.len) |t| { const b=self.routes.?.items[t]; for(a,0..) |c,p| { for(b,0..) |e,j| {
                    if(self.load(a)-self.stops.get(c).?.demand+self.stops.get(e).?.demand>self.capacity or self.load(b)-self.stops.get(e).?.demand+self.stops.get(c).?.demand>self.capacity) continue;
                    const before=self.length(a)+self.length(b); a[p]=e; b[j]=c; const gain=before-self.length(a)-self.length(b);
                    if(gain>0) { try self.out.line("exchange {d} (route {d}) with {d} (route {d}) gain {d}",.{c,r+1,e,t+1,gain}); changed=true; break :scan; }
                    a[p]=c; b[j]=e;
                } } } }
            } else {
                scan: for(self.routes.?.items,0..) |a,r| { for(r+1..self.routes.?.items.len) |t| { const b=self.routes.?.items[t]; for(0..a.len+1) |i| { for(0..b.len+1) |j| {
                    if(self.load(a[0..i])+self.load(b[j..])>self.capacity or self.load(b[0..j])+self.load(a[i..])>self.capacity) continue;
                    const x=at(a,i); const y=at(b,j); const gain=self.distance(x,at(a,i+1))+self.distance(y,at(b,j+1))-self.distance(x,at(b,j+1))-self.distance(y,at(a,i+1));
                    if(gain>0) {
                        try self.out.line("cross route {d} after {s} with route {d} after {s} gain {d}",.{r+1,try label(self.gpa,x),t+1,try label(self.gpa,y),gain});
                        self.routes.?.items[r]=try concatenate(self.gpa,a[0..i],b[j..]); self.routes.?.items[t]=try concatenate(self.gpa,b[0..j],a[i..]); changed=true; break :scan;
                    }
                } } } }
            }
            if(!changed) break; moves+=1; try self.normalize();
        }
        const lower=if(equal(command,"EXCHANGE")) "exchange" else if(equal(command,"CROSS")) "cross" else "relocate";
        if(equal(command,"EXCHANGE")) try self.out.line("{s}: moves {d}, length {d} -> {d}",.{lower,moves,initial,self.total()})
        else try self.out.line("{s}: moves {d}, routes {d} -> {d}, length {d} -> {d}",.{lower,moves,k0,self.routes.?.items.len,initial,self.total()});
    }
    fn command(self: *Workbench,line: Text) Error!void {
        const tokens=try words(self.gpa,line); const commandName=tokens[0]; const args=tokens[1..];
        if(equal(commandName,"DEPOT")) { self.depot=.{.x=number(args[0]),.y=number(args[1])}; try self.out.line("depot at ({d},{d})",.{self.depot.?.x,self.depot.?.y}); return; }
        if(equal(commandName,"START")) { self.start=clock(args[0]); try self.out.line("start {s}",.{try timeText(self.gpa,self.start)}); return; }
        if(equal(commandName,"STOP")) {
            const id=natural(args[0]); if(self.stops.contains(id)) return self.fail("stop {d} already exists",.{id});
            var item: Stop=.{.x=number(args[1]),.y=number(args[2]),.demand=number(args[3]),.service=number(args[4])};
            if(args.len>5) { item.open=clock(args[5]); item.close=clock(args[6]); if(item.open.?>item.close) return self.fail("invalid window",.{}); }
            try self.stops.put(self.gpa,id,item); self.tour=null; self.routes=null; try self.out.line("stop {d} added",.{id}); return;
        }
        if(equal(commandName,"REMOVE")) {
            const id=natural(args[0]); if(!self.stops.remove(id)) return self.fail("unknown stop {d}",.{id});
            if(self.stops.count()==0) { self.tour=null; self.routes=null; } else {
                if(self.tour) |p| self.tour=try without(self.gpa,p,id);
                if(self.routes!=null) { for(self.routes.?.items) |*p| p.*=try without(self.gpa,p.*,id); try self.normalize(); }
            }
            try self.out.line("stop {d} removed",.{id}); return;
        }
        if(equal(commandName,"LIST")) {
            if(self.depot) |depot| { try self.out.line("depot ({d},{d})",.{depot.x,depot.y}); } else try self.out.line("depot none",.{});
            try self.out.line("start {s}",.{try timeText(self.gpa,self.start)}); try self.out.line("stops {d}",.{self.stops.count()});
            for(try self.ids()) |id| { const item=self.stops.get(id).?; const window=if(item.open) |open| try std.fmt.allocPrint(self.gpa,"{s}-{s}",.{try timeText(self.gpa,open),try timeText(self.gpa,item.close)}) else "none"; try self.out.line("{d} at ({d},{d}) demand {d} service {d} window {s}",.{id,item.x,item.y,item.demand,item.service,window}); } return;
        }
        if(equal(commandName,"MATRIX")) {
            if(self.depot==null) return self.fail("no depot",.{}); const list=try concatenate(self.gpa,&.{0},try self.ids()); var width: usize=1;
            for(list) |a| { width=@max(width,(try label(self.gpa,a)).len); for(list) |b| width=@max(width,(try std.fmt.allocPrint(self.gpa,"{d}",.{self.distance(a,b)})).len); }
            try self.cell("",width); for(list) |id| { try self.out.add(" "); try self.cell(try label(self.gpa,id),width); } try self.out.add("\n");
            for(list) |a| { try self.cell(try label(self.gpa,a),width); for(list) |b| { try self.out.add(" "); try self.cell(try std.fmt.allocPrint(self.gpa,"{d}",.{self.distance(a,b)}),width); } try self.out.add("\n"); } return;
        }
        if(equal(commandName,"REPORT")) { try self.report(); return; }
        if(equal(commandName,"TOUR") or equal(commandName,"TWOOPT") or equal(commandName,"OROPT") or equal(commandName,"SWAP") or equal(commandName,"SPLIT") or equal(commandName,"TIMECHECK") and args.len==0) {
            if(self.tour==null) return self.fail("no tour",.{});
        } else if(equal(commandName,"ROUTES") or equal(commandName,"RELOCATE") or equal(commandName,"EXCHANGE") or equal(commandName,"CROSS") or equal(commandName,"ROUTEOPT") or equal(commandName,"TIMECHECK")) {
            if(self.routes==null) return self.fail("no plan",.{});
        } else try self.baseCheck();
        if(equal(commandName,"ORDER")) {
            const p=try self.gpa.alloc(usize,args.len); for(args,0..) |arg,i| { p[i]=natural(arg); if(!self.stops.contains(p[i])) return self.fail("unknown stop {d}",.{p[i]}); }
            var seen: std.AutoHashMapUnmanaged(usize,void)=.empty; for(p) |id| { if(seen.contains(id)) return self.fail("duplicate stop {d}",.{id}); try seen.put(self.gpa,id,{}); }
            if(p.len!=self.stops.count()) return self.fail("order has {d} stops, expected {d}",.{p.len,self.stops.count()}); self.tour=p; try self.out.line("order: {s} length {d}",.{try notation(self.gpa,p),self.length(p)});
        } else if(equal(commandName,"NEAREST") or equal(commandName,"INSERTION") or equal(commandName,"EXACT")) {
            if(equal(commandName,"EXACT") and self.stops.count()>10) return self.fail("too many stops for exact ({d})",.{self.stops.count()});
            var p: []usize=try self.gpa.alloc(usize,0);
            if(equal(commandName,"EXACT")) { p=try self.exact(); } else {
                const list=try self.ids(); var used: std.AutoHashMapUnmanaged(usize,void)=.empty;
                while(p.len<list.len) {
                    var best: Int=std.math.maxInt(Int); var candidate: usize=0; var position: usize=0;
                    for(list) |id| { if(used.contains(id)) continue;
                        if(equal(commandName,"NEAREST")) { const d=self.distance(at(p,p.len),id); if(d<best) { best=d; candidate=id; position=p.len; } }
                        else { for(0..p.len+1) |j| { const a=at(p,j); const b=at(p,j+1); const increase=self.distance(a,id)+self.distance(id,b)-self.distance(a,b); if(increase<best) { best=increase; candidate=id; position=j; } } }
                    }
                    p=try place(self.gpa,p,position,&.{candidate}); try used.put(self.gpa,candidate,{});
                }
            }
            self.tour=p; const lower=if(equal(commandName,"NEAREST")) "nearest" else if(equal(commandName,"INSERTION")) "insertion" else "exact";
            try self.out.line("{s}: {s} length {d}",.{lower,try notation(self.gpa,p),self.length(p)});
        } else if(equal(commandName,"TOUR")) { try self.out.line("tour: {s} length {d}",.{try notation(self.gpa,self.tour.?),self.length(self.tour.?)}); }
        else if(equal(commandName,"TWOOPT")) { const before=self.length(self.tour.?); const moves=try self.twoopt(self.tour.?,true); try self.out.line("twoopt: moves {d}, length {d} -> {d}",.{moves,before,self.length(self.tour.?)}); }
        else if(equal(commandName,"SWAP") or equal(commandName,"OROPT")) { try self.improveTour(commandName); }
        else if(equal(commandName,"TIMECHECK")) {
            if(args.len==0) { try self.out.line("timecheck tour depart {s}",.{try timeText(self.gpa,self.start)}); _=try self.simulate(self.tour.?,true); }
            else { const r=natural(args[0]); if(r>self.routes.?.items.len) return self.fail("no route {d}",.{r}); try self.out.line("timecheck route {d} depart {s}",.{r,try timeText(self.gpa,self.start)}); _=try self.simulate(self.routes.?.items[r-1],true); }
        } else if(equal(commandName,"BOUND")) { try self.bound(); }
        else if(equal(commandName,"VRP") or equal(commandName,"SPLIT") or equal(commandName,"SWEEP")) { try self.construct(commandName,args); }
        else if(equal(commandName,"ROUTES")) { try self.out.line("plan: capacity {d}, routes {d}, length {d}",.{self.capacity,self.routes.?.items.len,self.total()}); try self.routeLines(); }
        else if(equal(commandName,"RELOCATE") or equal(commandName,"EXCHANGE") or equal(commandName,"CROSS")) { try self.improve(commandName); }
        else if(equal(commandName,"ROUTEOPT")) {
            const before=self.total(); for(self.routes.?.items,0..) |p,i| { const old=self.length(p); const moves=try self.twoopt(p,false); try self.out.line("route {d}: moves {d}, length {d} -> {d}",.{i+1,moves,old,self.length(p)}); }
            try self.normalize(); try self.out.line("routeopt: length {d} -> {d}",.{before,self.total()});
        }
    }
    fn cell(self: *Workbench,text: Text,width: usize) Error!void { for(text.len..width) |_| try self.out.add(" "); try self.out.add(text); }
    fn improveTour(self: *Workbench,commandName: Text) Error!void {
        const before=self.length(self.tour.?); var moves: usize=0;
        while(true) {
            const p=self.tour.?; const old=self.length(p); var changed=false;
            if(equal(commandName,"SWAP")) {
                scan: for(0..p.len) |i| { for(i+1..p.len) |j| {
                    const a=p[i]; const b=p[j]; p[i]=b; p[j]=a; const gain=old-self.length(p);
                    if(gain>0) { try self.out.line("swap {d} and {d} gain {d}",.{a,b,gain}); changed=true; break :scan; } p[i]=a; p[j]=b;
                } }
            } else {
                scan: for(1..4) |size| { if(size>p.len) continue; for(0..p.len-size+1) |i| {
                    const segment=p[i..i+size]; const rest=try concatenate(self.gpa,p[0..i],p[i+size..]);
                    const removed=self.distance(at(p,i),segment[0])+self.distance(segment[size-1],at(p,i+size+1))-self.distance(at(p,i),at(p,i+size+1));
                    for(0..rest.len+1) |j| { if(j==i) continue; const u=at(rest,j); const v=at(rest,j+1); const gain=removed-self.distance(u,segment[0])-self.distance(segment[size-1],v)+self.distance(u,v);
                        if(gain>0) { var names: Builder=.{.gpa=self.gpa}; for(segment,0..) |id,k| { if(k>0) try names.add("-"); try names.print("{d}",.{id}); }
                            try self.out.line("move {s} after {s} gain {d}",.{names.bytes.items,try label(self.gpa,u),gain}); self.tour=try place(self.gpa,rest,j,segment); changed=true; break :scan;
                        }
                    }
                } }
            }
            if(!changed) break; moves+=1;
        }
        try self.out.line("{s}: moves {d}, length {d} -> {d}",.{if(equal(commandName,"SWAP")) "swap" else "oropt",moves,before,self.length(self.tour.?)});
    }
    fn construct(self: *Workbench,commandName: Text,args: []const Text) Error!void {
        const q=number(args[0]); try self.capacityCheck(q); const list=try self.ids();
        const limit: ?Int=if(args.len>1) number(args[1]) else null;
        if(equal(commandName,"VRP")) { if(limit) |boundValue| for(list) |id| { if(2*self.distance(0,id)>boundValue) return self.fail("stop {d} too far for limit {d}",.{id,boundValue}); }; }
        var routes: std.ArrayList([]usize)=.empty; var merges: usize=0;
        if(equal(commandName,"VRP")) {
            for(list) |id| try routes.append(self.gpa,try self.gpa.dupe(usize,&.{id}));
            const Saving=struct { a: usize,b: usize,value: Int }; var savings: std.ArrayList(Saving)=.empty;
            for(list,0..) |a,i| { for(list[i+1..]) |b| { const value=self.distance(0,a)+self.distance(0,b)-self.distance(a,b); if(value>0) try savings.append(self.gpa,.{.a=a,.b=b,.value=value}); } }
            std.mem.sort(Saving,savings.items,{},struct { fn less(_: void,a: Saving,b: Saving) bool { return a.value>b.value or a.value==b.value and (a.a<b.a or a.a==b.a and a.b<b.b); } }.less);
            for(savings.items) |saving| {
                var r: usize=0; var t: usize=0;
                for(routes.items,0..) |p,k| { for(p) |id| { if(id==saving.a) r=k; if(id==saving.b) t=k; } }
                if(r==t) continue; const originalA=routes.items[r]; const originalB=routes.items[t];
                if((originalA[0]!=saving.a and originalA[originalA.len-1]!=saving.a) or (originalB[0]!=saving.b and originalB[originalB.len-1]!=saving.b) or self.load(originalA)+self.load(originalB)>q) continue;
                const a=try self.gpa.dupe(usize,originalA); const b=try self.gpa.dupe(usize,originalB); if(a[0]==saving.a) reverse(a); if(b[b.len-1]==saving.b) reverse(b);
                const combined=try concatenate(self.gpa,a,b); if(limit!=null and self.length(combined)>limit.?) continue; routes.items[r]=combined; _=routes.orderedRemove(t); merges+=1;
            }
        } else if(equal(commandName,"SPLIT")) {
            const p=self.tour.?; const costs=try self.gpa.alloc(Int,p.len+1); const previous=try self.gpa.alloc(usize,p.len+1); costs[0]=0;
            for(1..p.len+1) |j| { costs[j]=std.math.maxInt(Int); for(0..j) |i| { if(self.load(p[i..j])>q) continue; const value=costs[i]+self.length(p[i..j]); if(value<costs[j]) { costs[j]=value; previous[j]=i; } } }
            var j=p.len; while(j>0) { const i=previous[j]; try routes.append(self.gpa,try self.gpa.dupe(usize,p[i..j])); j=i; }
        } else {
            std.mem.sort(usize,list,self,angleLess); var current: std.ArrayList(usize)=.empty;
            for(list) |id| { if(self.load(current.items)+self.stops.get(id).?.demand>q) { try routes.append(self.gpa,current.items); current=.empty; } try current.append(self.gpa,id); }
            try routes.append(self.gpa,current.items);
        }
        self.routes=routes; self.capacity=q; try self.normalize();
        if(equal(commandName,"VRP")) try self.out.line("vrp: capacity {d}, merges {d}, routes {d}, length {d}",.{q,merges,self.routes.?.items.len,self.total()})
        else try self.out.line("{s}: capacity {d}, routes {d}, length {d}",.{if(equal(commandName,"SPLIT")) "split" else "sweep",q,self.routes.?.items.len,self.total()});
        try self.routeLines();
    }
    fn report(self: *Workbench) Error!void {
        var demand: Int=0; var service: Int=0; var windows: usize=0; var iterator=self.stops.valueIterator();
        while(iterator.next()) |item| { demand+=item.demand; service+=item.service; if(item.open!=null) windows+=1; }
        try self.out.line("report: stops {d}, demand {d}, service {d}, windows {d}",.{self.stops.count(),demand,service,windows});
        if(self.tour) |p| { const r=try self.simulate(p,false); try self.out.line("tour: length {d}, return {s}, violations {d}, lateness {d}",.{r.travel,try timeText(self.gpa,r.returned),r.violations,r.lateness}); } else try self.out.line("tour: none",.{});
        if(self.routes) |routes| {
            var returned: Int=0; var violations: Int=0; var lateness: Int=0;
            for(routes.items) |p| { const r=try self.simulate(p,false); returned=@max(returned,r.returned); violations+=r.violations; lateness+=r.lateness; }
            const denominator=@as(Int,@intCast(routes.items.len))*self.capacity; const u=@divTrunc(2000*demand+denominator,2*denominator);
            try self.out.line("plan: capacity {d}, routes {d}, length {d}, utilization {d}.{d}%, return {s}, violations {d}, lateness {d}",.{self.capacity,routes.items.len,self.total(),@divTrunc(u,10),@mod(u,10),try timeText(self.gpa,returned),violations,lateness});
        } else try self.out.line("plan: none",.{});
    }
};
fn angleLess(w: *Workbench,a: usize,b: usize) bool {
    const p=w.stops.get(a).?; const q=w.stops.get(b).?; const depot=w.depot.?;
    const ax=p.x-depot.x; const ay=p.y-depot.y; const bx=q.x-depot.x; const by=q.y-depot.y;
    const az=ax==0 and ay==0; const bz=bx==0 and by==0; if(az!=bz) return az; if(az) return a<b;
    const ah=ay>0 or ay==0 and ax>0; const bh=by>0 or by==0 and bx>0; if(ah!=bh) return ah;
    const cross=ax*by-ay*bx; if(cross!=0) return cross>0; const da=abs(ax)+abs(ay); const db=abs(bx)+abs(by); return da<db or da==db and a<b;
}
fn without(gpa: Allocator,p: []const usize,id: usize) Allocator.Error![]usize { var result: std.ArrayList(usize)=.empty; for(p) |value| if(value!=id) try result.append(gpa,value); return result.items; }
const Exact = struct {
    w: *Workbench,ids: []const usize,
    memo: std.AutoHashMapUnmanaged(struct { mask: usize,last: usize },Int)=.empty,
    fn cost(self: *Exact,mask: usize,last: usize) Error!Int {
        if(mask==0) return self.w.distance(last,0); const key=.{.mask=mask,.last=last}; if(self.memo.get(key)) |value| return value;
        var best: Int=std.math.maxInt(Int);
        for(self.ids,0..) |id,i| { const bit=@as(usize,1)<<@intCast(i); if(mask&bit!=0) best=@min(best,self.w.distance(last,id)+try self.cost(mask^bit,id)); }
        try self.memo.put(self.w.gpa,key,best); return best;
    }
};
pub fn main(init: std.process.Init) !void {
    var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit(); const gpa=arena.allocator();
    var inputBuffer: [8192]u8=undefined; var input=std.Io.File.stdin().readerStreaming(init.io,&inputBuffer); const text=try input.interface.allocRemaining(gpa,.unlimited);
    var lines=std.mem.splitScalar(u8,text,'\n'); const count=natural(std.mem.trimEnd(u8,lines.next().?,"\r")); var out: Builder=.{.gpa=gpa}; var w: Workbench=.{.gpa=gpa,.out=&out};
    for(0..count) |_| { const line=std.mem.trimEnd(u8,lines.next().?,"\r"); w.command(line) catch |err| { if(err!=error.Invalid) return err; try out.line("{s}",.{failure}); }; }
    var outputBuffer: [8192]u8=undefined; var output=std.Io.File.stdout().writerStreaming(init.io,&outputBuffer); try output.interface.writeAll(out.bytes.items); try output.interface.flush();
}
