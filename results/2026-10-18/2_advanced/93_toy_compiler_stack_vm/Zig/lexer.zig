const std=@import("std");
pub var allocator:std.mem.Allocator=undefined;
pub fn alloc(comptime T:type,n:usize) []T { return allocator.alloc(T,n) catch @panic("allocation failed"); }
pub fn create(comptime T:type,v:T) *T { const p=allocator.create(T) catch @panic("allocation failed"); p.*=v; return p; }
pub fn append(comptime T:type,a:*std.ArrayList(T),v:T) void { a.append(allocator,v) catch @panic("allocation failed"); }
pub fn fmt(comptime s:[]const u8,a:anytype) []const u8 { return std.fmt.allocPrint(allocator,s,a) catch @panic("allocation failed"); }
pub fn eq(a:[]const u8,b:[]const u8) bool { return std.mem.eql(u8,a,b); }
pub fn spaces(n:usize) []const u8 { const s=alloc(u8,n); @memset(s,' '); return s; }
pub const Text=struct { data:std.ArrayList(u8)=.empty,pub fn put(self:*Text,comptime s:[]const u8,a:anytype) void { self.data.appendSlice(allocator,fmt(s,a)) catch @panic("allocation failed"); } pub fn line(self:*Text,comptime s:[]const u8,a:anytype) void { self.put(s,a); self.put("\n",.{}); } };
pub const Position=struct { line:usize,column:usize,pub fn str(self:Position) []const u8 { return fmt("{d}:{d}",.{self.line,self.column}); } };
pub fn before(a:Position,b:Position) bool { return a.line<b.line or (a.line==b.line and a.column<b.column); }
pub const Failure=struct { kind:[]const u8,position:Position,message:[]const u8 };
pub const Token=struct { kind:enum{identifier,keyword,integer,symbol,end},text:[]const u8,position:Position };
pub const Result=struct { tokens:[]const Token,failure:?Failure=null };
pub fn scan(source:[]const u8,first_line:usize) Result {
    var tokens:std.ArrayList(Token)=.empty; var at:usize=0; var line=first_line; var column:usize=1; var failure:?Failure=null;
    while(at<source.len) {
        if(source[at]==' ' or source[at]=='\n') { if(source[at]=='\n') { line+=1; column=1; } else column+=1; at+=1; continue; }
        const start=at; const pos=Position{.line=line,.column=column}; var kind:@FieldType(Token,"kind")=.symbol;
        if(std.mem.startsWith(u8,source[at..],"//")) { while(at<source.len and source[at]!='\n') : (at+=1) { column+=1; } continue; }
        if(std.mem.startsWith(u8,source[at..],"/*")) { const end=std.mem.indexOf(u8,source[at+2..],"*/") orelse { failure=.{.kind="lexical",.position=pos,.message="unterminated comment"}; break; }; const stop=at+2+end+2; while(at<stop) : (at+=1) { if(source[at]=='\n') { line+=1; column=1; } else column+=1; } continue; }
        if(std.ascii.isAlphabetic(source[at]) or source[at]=='_') { at+=1; while(at<source.len and (std.ascii.isAlphanumeric(source[at]) or source[at]=='_')) : (at+=1) {} kind=.identifier; for([_][]const u8{"int","bool","void","true","false","if","else","while","for","break","continue","return","print","read"}) |keyword| if(eq(source[start..at],keyword)) { kind=.keyword; break; }; }
        else if(std.ascii.isDigit(source[at])) { at+=1; while(at<source.len and std.ascii.isDigit(source[at])) : (at+=1) {} kind=.integer; const n=std.fmt.parseInt(i64,source[start..at],10) catch std.math.maxInt(i64); if(n>2147483647) { failure=.{.kind="lexical",.position=pos,.message="integer literal too large"}; break; } }
        else { var pair=false; if(at+1<source.len) for([_][]const u8{"<=",">=","==","!=","&&","||"}) |symbol| if(eq(source[at..at+2],symbol)) { pair=true; break; }; if(pair) at+=2 else if(std.mem.indexOfScalar(u8,"+-*/%<>=!(){}[],;",source[at])!=null) at+=1 else { failure=.{.kind="lexical",.position=pos,.message=fmt("unexpected character '{c}'",.{source[at]})}; break; } }
        append(Token,&tokens,.{.kind=kind,.text=source[start..at],.position=pos}); column+=at-start;
    }
    const trimmed=std.mem.trimEnd(u8,source,"\n"); const last_start=if(std.mem.lastIndexOfScalar(u8,trimmed,'\n')) |i| i+1 else 0; var last_line=first_line; for(trimmed) |c| if(c=='\n') { last_line+=1; };
    append(Token,&tokens,.{.kind=.end,.text="",.position=.{.line=last_line,.column=trimmed.len-last_start+1}}); return .{.tokens=tokens.items,.failure=failure};
}
pub fn read(io:std.Io,path:[]const u8) ![]const u8 { return std.Io.Dir.cwd().readFileAlloc(io,path,allocator,.unlimited); }
pub fn write(io:std.Io,name:[]const u8,text:Text) !void { try std.Io.Dir.cwd().writeFile(io,.{.sub_path=fmt("output/{s}",.{name}),.data=text.data.items}); }
