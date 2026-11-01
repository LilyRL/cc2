const std = @import("std");

pub const Constant = union(Constant.Type) {
    int: i32,
    uint: u32,
    long: i64,
    ulong: u64,
    float: f32,
    double: f64,

    pub const Type = enum {
        int,
        uint,
        long,
        ulong,
        float,
        double,
    };

    pub fn fmt(self: Constant, writer: anytype) !void {
        switch (self) {
            .int => try writer.print("int({d})", .{self.int}),
            .uint => try writer.print("uint({d})", .{self.uint}),
            .long => try writer.print("long({d})", .{self.long}),
            .ulong => try writer.print("ulong({d})", .{self.ulong}),
            .float => try writer.print("float({d})", .{self.float}),
            .double => try writer.print("double({d})", .{self.double}),
        }
    }
};
