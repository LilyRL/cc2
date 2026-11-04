const std = @import("std");
const Identifier = @This();

id: u32,

fn raw(n: u32) Identifier {
    return .{ .id = n };
}

pub const Interner = struct {
    str_to_id: std.StringHashMapUnmanaged(u32),
    id_to_str: IdToStr,
    // the number of identifiers with this name that have been created already
    unique_identifier_counts: std.StringHashMapUnmanaged(u32),
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,

    const IdToStr = std.HashMap(u32, []const u8, std.hash_map.AutoContext(u32), 75);

    pub fn init(arena: std.mem.Allocator, gpa: std.mem.Allocator) Interner {
        return .{
            .arena = arena,
            .str_to_id = std.StringHashMapUnmanaged(u32).empty,
            .unique_identifier_counts = std.StringHashMapUnmanaged(u32).empty,
            .id_to_str = IdToStr.init(gpa),
            .gpa = gpa,
        };
    }

    pub fn get(self: *const Interner, id: Identifier) ?[]const u8 {
        return self.id_to_str.get(id.id);
    }

    pub fn intern(self: *Interner, s: []const u8) !Identifier {
        if (self.str_to_id.get(s)) |id| return raw(id);
        const owned = try self.arena.dupe(u8, s);
        const id: u32 = @intCast(self.str_to_id.count());
        try self.str_to_id.put(self.gpa, s, id);
        try self.id_to_str.put(id, owned);
        return raw(id);
    }

    fn randId(self: *Interner, s: []const u8) !u32 {
        const ptr = self.unique_identifier_counts.getPtr(s);
        if (ptr) |count_ptr| {
            const count = count_ptr.*;
            count_ptr.* += 1;
            return count;
        } else {
            try self.unique_identifier_counts.put(self.gpa, s, 1);
            return 0;
        }
    }

    pub fn random(self: *Interner, s: []const u8) !Identifier {
        const CHARS: *const [62]u8 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

        var n = try self.randId(s);
        var output_len: usize = 0;
        var output: [10]u8 = undefined;

        while (n != 0) {
            const q = n % 62;
            n /= 62;

            output[output_len] = CHARS[q];
            output_len += 1;
        }

        const buf = try self.arena.alloc(u8, s.len + output_len);
        std.mem.copyForwards(u8, buf, s);
        std.mem.copyForwards(u8, buf[s.len..], output[0..output_len]);

        const id: u32 = @intCast(self.str_to_id.count());
        try self.str_to_id.put(self.gpa, buf, id);
        try self.id_to_str.put(id, buf);
        return raw(id);
    }

    pub fn deinit(self: *Interner) void {
        self.str_to_id.deinit(self.gpa);
        self.id_to_str.deinit();
        self.unique_identifier_counts.deinit(self.gpa);
    }
};
