const std = @import("std");
const p = @import("protocol.zig");
const masks = @import("masks.zig");
const Client = @import("clients.zig").Client;
pub const Member = struct {
    client: *Client,
    op: bool = false,
    voice: bool = false,
    pub fn status(self: Member) []const u8 {
        return if (self.op) "@" else if (self.voice) "+" else "";
    }
    pub fn display(self: Member) []const u8 {
        return p.fmt("{s}{s}", .{ self.status(), self.client.nickname.? });
    }
};
pub const Ban = struct { mask: []const u8, setter: []const u8, time: i64 };
pub const Channel = struct {
    index: usize,
    name: []const u8,
    created: i64,
    members: std.ArrayList(Member) = .empty,
    topic: []const u8 = "",
    topic_setter: []const u8 = "",
    topic_time: i64 = 0,
    bans: std.ArrayList(Ban) = .empty,
    flag_i: bool = false,
    flag_m: bool = false,
    flag_n: bool = true,
    flag_t: bool = true,
    key: []const u8 = "",
    limit: i64 = 0,
    peak: usize = 0,
    messages: i64 = 0,
    active: bool = true,
    pub fn member(self: *Channel, client: *Client) ?*Member {
        for (self.members.items) |*entry| if (entry.client == client) return entry;
        return null;
    }
    pub fn flag(self: Channel, character: u8) bool {
        return switch (character) {
            'i' => self.flag_i,
            'm' => self.flag_m,
            'n' => self.flag_n,
            't' => self.flag_t,
            else => unreachable,
        };
    }
    pub fn setFlag(self: *Channel, character: u8, value: bool) void {
        switch (character) {
            'i' => self.flag_i = value,
            'm' => self.flag_m = value,
            'n' => self.flag_n = value,
            't' => self.flag_t = value,
            else => unreachable,
        }
    }
    pub fn add(self: *Channel, client: *Client, op: bool) void {
        p.append(Member, &self.members, .{ .client = client, .op = op });
        p.append(usize, &client.channels, self.index);
        self.peak = @max(self.peak, self.members.items.len);
    }
    pub fn remove(self: *Channel, client: *Client) void {
        for (self.members.items, 0..) |entry, i| if (entry.client == client) {
            _ = self.members.orderedRemove(i);
            break;
        };
        p.erase(&client.channels, self.index);
    }
    pub fn nameList(self: *Channel, viewer: *Client) []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        const inside = self.member(viewer) != null;
        for (self.members.items) |entry| if (inside or !entry.client.invisible) p.append([]const u8,
             &names, entry.display());
        return p.join(names.items, " ");
    }
    pub fn modeDisplay(self: Channel, include_key: bool) []const u8 {
        var out: p.Text = .{};
        out.add("+{s}{s}{s}{s}{s}{s}", .{ if (self.flag_i) "i" else "", if (self.key.len > 0) "k" else "",
             if (self.limit > 0) "l" else "", if (self.flag_m) "m" else "", if (self.flag_n) "n" else "",
             if (self.flag_t) "t" else "" });
        if (include_key and self.key.len > 0) out.add(" {s}", .{self.key});
        if (self.limit > 0) out.add(" {d}", .{self.limit});
        return out.value();
    }
    pub fn banned(self: Channel, client: *Client) bool {
        for (self.bans.items) |ban| if (masks.matches(ban.mask, client.prefix())) return true;
        return false;
    }
    pub fn canSpeak(self: *Channel, client: *Client) bool {
        const entry = self.member(client);
        const privileged = if (entry) |m| m.op or m.voice else false;
        return (entry != null or !self.flag_n) and (!self.flag_m or privileged) and (privileged or !self.banned(client));
    }
};
