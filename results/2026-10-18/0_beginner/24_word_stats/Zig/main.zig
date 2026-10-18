const std = @import("std");

fn fixed(out: *std.Io.Writer, value: f64, places: usize) !void {
    var scale: u64 = 1;
    for (0..places) |_| scale *= 10;
    const scaled: u64 = @intFromFloat(@floor(@abs(value) * @as(f64, @floatFromInt(scale)) + 0.5));
    if (value < 0) try out.writeByte('-');
    try out.print("{d}", .{scaled / scale});
    if (places > 0) try out.writeByte('.');
    var divisor = scale / 10;
    while (divisor > 0) : (divisor /= 10) {
        try out.writeByte('0' + @as(u8, @intCast((scaled / divisor) % 10)));
    }
}


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var words=std.mem.splitScalar(u8,"we planted beans and carrots in the garden behind our old house",' ');
    var count:usize=0; var total:usize=0; var longest:[]const u8=""; var shortest:[]const u8="";
    while(words.next()) |word| {
        if(count==0 or word.len>longest.len) longest=word;
        if(count==0 or word.len<shortest.len) shortest=word;
        count+=1; total+=word.len;
    }
    try out.print("words: {d}\nlongest: {s}\nshortest: {s}\naverage length: ", .{count,longest,shortest});
    try fixed(out,@as(f64,@floatFromInt(total))/@as(f64,@floatFromInt(count)),2);
    try out.writeByte('\n');
    try out.flush();
}
