const std = @import("std");

fn det(matrix:[5][5]i64,n:usize) i64 {
    if(n==1) return matrix[0][0];var result:i64=0;
    for(0..n) |j| {var minor:[5][5]i64=undefined;
        for(1..n) |r| {var col:usize=0;for(0..n) |c| {if(c!=j) {minor[r-1][col]=matrix[r][c];col+=1;}}}
        const term=matrix[0][j]*det(minor,n-1);result+=if(j%2==0) term else -term;
    }
    return result;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    {const matrix=[5][5]i64{.{2,-3,1,0,0},.{5,4,-2,0,0},.{-1,6,3,0,0},.{0,0,0,0,0},.{0,0,0,0,0}};
    try out.print("det(3x3) = {d}\n", .{det(matrix,3)});}
    {const matrix=[5][5]i64{.{3,0,-2,5,0},.{1,4,7,-3,0},.{-6,2,1,8,0},.{9,-5,3,2,0},.{0,0,0,0,0}};
    try out.print("det(4x4) = {d}\n", .{det(matrix,4)});}
    {const matrix=[5][5]i64{.{4,-1,7,0,-3},.{2,8,-5,6,1},.{-9,3,2,-4,5},.{6,0,-7,3,-2},.{1,-6,4,9,8}};
    try out.print("det(5x5) = {d}\n", .{det(matrix,5)});}

    try out.flush();
}
