const std = @import("std");
const p = @import("protocol.zig");
pub const Client = struct {
    identifier: []const u8,
    hostname: []const u8,
    connection_time: i64,
    nickname: ?[]const u8 = null,
    username: ?[]const u8 = null,
    realname: []const u8 = "",
    invisible: bool = false,
    registered: bool = false,
    registration_time: ?i64 = null,
    last_speaking: ?i64 = null,
    ping_sent: ?i64 = null,
    last_received: i64,
    tokens: i64,
    refill_time: ?i64 = null,
    queue: std.ArrayList([]const u8) = .empty,
    channels: std.ArrayList(usize) = .empty,
    invites: std.ArrayList(usize) = .empty,
    away: []const u8 = "",
    received: i64 = 0,
    sent: i64 = 0,
    active: bool = true,
    pub fn addressee(self: Client) []const u8 {
        return self.nickname orelse "*";
    }
    pub fn prefix(self: Client) []const u8 {
        return p.fmt("{s}!{s}@{s}", .{ self.nickname.?, self.username.?, self.hostname });
    }
    pub fn mode(self: Client) []const u8 {
        return if (self.invisible) "+i" else "+";
    }
    pub fn useToken(self: *Client, time: i64, capacity: i64, interval: i64) void {
        if (self.tokens == capacity) self.refill_time = time + interval;
        self.tokens -= 1;
    }
    pub fn refill(self: *Client, time: i64, capacity: i64, interval: i64) void {
        if (self.refill_time == time) {
            self.tokens += 1;
            self.refill_time = if (self.tokens < capacity) time + interval else null;
        }
    }
};
