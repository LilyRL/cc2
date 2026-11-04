pub const Type = union(enum) { int, long, uint, ulong, float, double, function: *FunctionType };
pub const StorageClass = enum { static, @"extern", none };

pub const FunctionType = struct {
    parameters: []Type,
    defined: bool,
    return_type: Type,
};
