pub fn sliceContains(comptime T: type, haystack: []const T, needle: T) bool {
    for (haystack) |thing| {
        if (thing == needle) {
            return true;
        }
    }
    return false;
}

pub fn bruteForceDuplicateCheck(comptime T: type, haystack: []const T) bool {
    for (haystack, 0..) |thing, i| {
        for (haystack[i + 1 ..]) |other| {
            if (thing == other) {
                return true;
            }
        }
    }
    return false;
}
