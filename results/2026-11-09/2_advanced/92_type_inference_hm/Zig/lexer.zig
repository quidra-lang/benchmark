const std=@import("std");
const u=@import("unifier.zig");
pub const Token=struct { kind:enum { name,keyword,integer,string,typevar,symbol,invalid,eof },value:[]const u8,spelling:[]const u8,position:u.Position };
pub fn scan(source:[]const u8,file:usize) []const Token {
    var out:std.ArrayList(Token)=.empty; var at:usize=0; var line:usize=1; var column:usize=1;
    while(at<source.len) {
        if(source[at]==' ' or source[at]=='\n') { if(source[at]=='\n') { line+=1; column=1; } else column+=1; at+=1; continue; }
        const start=at; const position=u.Position{.file=file,.line=line,.column=column}; var kind:@FieldType(Token,"kind")=.symbol; var value:[]const u8=undefined;
        if(std.mem.startsWith(u8,source[at..],"(*")) {
            const end=std.mem.indexOf(u8,source[at+2..],"*)"); if(end==null) { u.append(Token,&out,.{.kind=.invalid,.value="unterminated comment",.spelling=source[at..],.position=position}); while(at<source.len) : (at+=1) if(source[at]=='\n') { line+=1; column=1; } else { column+=1; }; break; }
            const stop=at+2+end.?+2; while(at<stop) : (at+=1) { if(source[at]=='\n') { line+=1; column=1; } else column+=1; } continue;
        } else if(std.ascii.isDigit(source[at])) { at+=1; while(at<source.len and std.ascii.isDigit(source[at])) : (at+=1) {} value=source[start..at]; kind=.integer; const n=std.fmt.parseInt(i64,value,10) catch std.math.maxInt(i64); if(n>2147483647) { kind=.invalid; value="integer literal too large"; } }
        else if(std.ascii.isAlphabetic(source[at]) or source[at]=='_') { at+=1; while(at<source.len and (std.ascii.isAlphanumeric(source[at]) or source[at]=='_' or source[at]=='\'')) : (at+=1) {} kind=.name; value=source[start..at]; for([_][]const u8{"let","rec","and","in","fun","if","then","else","match","with","true","false","mod","val"}) |word| if(u.eq(value,word)) { kind=.keyword; break; }; }
        else if(source[at]=='\'' and at+1<source.len and source[at+1]>='a' and source[at+1]<='z') { at+=2; while(at<source.len and (std.ascii.isAlphanumeric(source[at]) or source[at]=='_')) : (at+=1) {} kind=.typevar; value=source[start..at]; }
        else if(source[at]=='"') {
            at+=1; var decoded:u.Text=.{}; var invalid=false;
            while(at<source.len and source[at]!='"' and source[at]!='\n') {
                if(source[at]=='\\' and at+1<source.len and source[at+1]!='\n') { at+=1; const c:u8=switch(source[at]) {'n'=>'\n','t'=>'\t','\\'=>'\\','"'=>'"',else=>blk:{ invalid=true; break :blk source[at]; }}; decoded.put("{c}",.{c}); at+=1; }
                else { decoded.put("{c}",.{source[at]}); at+=1; }
            }
            if(at==source.len or source[at]!='"') { kind=.invalid; value="unterminated string"; } else { at+=1; kind=if(invalid) .invalid else .string; value=if(invalid) "invalid escape sequence" else decoded.data.items; }
        } else {
            var matched=false; if(at+1<source.len) for([_][]const u8{";;","->","::","||","&&","<=",">=","<>"}) |s| if(u.eq(source[at..at+2],s)) { at+=2; matched=true; break; };
            if(!matched) { if(std.mem.indexOfScalar(u8,":;=<>+-*/^()[],|",source[at])==null) { kind=.invalid; value=u.fmt("illegal character '{c}'",.{source[at]}); } at+=1; }
            if(kind!=.invalid) value=source[start..at];
        }
        u.append(Token,&out,.{.kind=kind,.value=value,.spelling=source[start..at],.position=position}); column+=at-start;
    }
    u.append(Token,&out,.{.kind=.eof,.value="",.spelling="",.position=.{.file=file,.line=line,.column=column}}); return out.items;
}
