const std = @import("std");
const Identifier = @This();

id: u32,

fn raw(n: u32) Identifier {
    return .{ .id = n };
}

pub const Interner = struct {
    str_to_id: std.StringHashMapUnmanaged(u32),
    id_to_str: IdToStr,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,

    const IdToStr = std.HashMap(u32, []const u8, std.hash_map.AutoContext(u32), 75);

    pub fn init(arena: std.mem.Allocator, gpa: std.mem.Allocator) Interner {
        return .{
            .arena = arena,
            .str_to_id = std.StringHashMapUnmanaged(u32).empty,
            .id_to_str = IdToStr.init(gpa),
            .gpa = gpa,
        };
    }

    pub fn get(self: *Interner, id: Identifier) ?[]const u8 {
        return self.id_to_str.get(id.id);
    }

    pub fn intern(self: *Interner, s: []const u8) !Identifier {
        if (self.str_to_id.get(s)) |id| return raw(id);
        const owned = try self.arena.dupe(u8, s);
        const id: u32 = @intCast(self.str_to_id.count());
        try self.str_to_id.put(self.gpa, s, id);
        try self.id_to_str.put(id, owned);
        return .{ .id = id };
    }

    pub fn deinit(self: *Interner) void {
        self.str_to_id.deinit(self.gpa);
        self.id_to_str.deinit();
    }
};
