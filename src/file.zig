const std = @import("std");
const lib = @import("root.zig");

const File = @This();

pub const FileId = struct {
    raw: u32,

    fn new(raw: u32) FileId {
        return .{ .raw = raw };
    }
};

source: []const u8,
name: []const u8,
linemap: std.ArrayList(usize),
id: FileId,

fn generateLinemap(source: []const u8, gpa: std.mem.Allocator) !std.ArrayList(usize) {
    var linemap: std.ArrayList(usize) = .empty;
    try linemap.append(gpa, 0);

    for (source, 0..) |c, i| {
        if (c == '\n') {
            try linemap.append(gpa, i + 1);
        }
    }

    return linemap;
}

pub const Store = struct {
    map: FileMap,
    gpa: std.mem.Allocator,

    const FileMap = std.HashMap(u64, File, std.hash_map.AutoContext(u64), 75);

    pub fn init(gpa: std.mem.Allocator) Store {
        return .{ .map = FileMap.init(gpa), .gpa = gpa };
    }

    pub fn newFile(self: *Store, name: []const u8, source: []const u8) !File {
        const id = self.map.count();
        const linemap = try generateLinemap(source, self.gpa);

        return .{
            .linemap = linemap,
            .source = source,
            .name = name,
            .id = FileId.new(id),
        };
    }

    pub fn get(self: *const Store, id: FileId) ?File {
        return self.map.get(id.raw);
    }

    pub fn add(self: *Store, file: File) !void {
        try self.map.put(file.id.raw, file);
    }

    pub fn deinit(self: *Store) void {
        var iter = self.map.iterator();
        while (iter.next()) |i| {
            const value = i.value_ptr;
            value.linemap.deinit(self.gpa);
        }

        self.map.deinit();
    }
};
