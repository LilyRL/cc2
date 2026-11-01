pub const fg = struct {
    pub const red = fg_ansi(.red);
    pub const green = fg_ansi(.green);
    pub const yellow = fg_ansi(.yellow);
    pub const blue = fg_ansi(.blue);
    pub const magenta = fg_ansi(.magenta);
    pub const cyan = fg_ansi(.cyan);
    pub const black = fg_ansi(.black);
    pub const white = fg_ansi(.white);

    pub const rainbow = [6][]const u8{
        fg_ansi(.red),
        fg_ansi(.yellow),
        fg_ansi(.green),
        fg_ansi(.cyan),
        fg_ansi(.blue),
        fg_ansi(.magenta),
    };

    pub const bold = struct {
        pub const red = bold_ansi(.red);
        pub const green = bold_ansi(.green);
        pub const yellow = bold_ansi(.yellow);
        pub const blue = bold_ansi(.blue);
        pub const magenta = bold_ansi(.magenta);
        pub const cyan = bold_ansi(.cyan);
        pub const black = bold_ansi(.black);
        pub const white = bold_ansi(.white);

        pub const rainbow = [6][]const u8{
            bold_ansi(.red),
            bold_ansi(.yellow),
            bold_ansi(.green),
            bold_ansi(.cyan),
            bold_ansi(.blue),
            bold_ansi(.magenta),
        };

        const underline = struct {
            pub const red = bold_underline_ansi(.red);
            pub const green = bold_underline_ansi(.green);
            pub const yellow = bold_underline_ansi(.yellow);
            pub const blue = bold_underline_ansi(.blue);
            pub const magenta = bold_underline_ansi(.magenta);
            pub const cyan = bold_underline_ansi(.cyan);
            pub const black = bold_underline_ansi(.black);
            pub const white = bold_underline_ansi(.white);

            pub const rainbow = [6][]const u8{
                bold_underline_ansi(.red),
                bold_underline_ansi(.yellow),
                bold_underline_ansi(.green),
                bold_underline_ansi(.cyan),
                bold_underline_ansi(.blue),
                bold_underline_ansi(.magenta),
            };
        };
    };

    pub const underline = struct {
        pub const red = underline_ansi(.red);
        pub const green = underline_ansi(.green);
        pub const yellow = underline_ansi(.yellow);
        pub const blue = underline_ansi(.blue);
        pub const magenta = underline_ansi(.magenta);
        pub const cyan = underline_ansi(.cyan);
        pub const black = underline_ansi(.black);
        pub const white = underline_ansi(.white);

        pub const rainbow = [6][]const u8{
            underline_ansi(.red),
            underline_ansi(.yellow),
            underline_ansi(.green),
            underline_ansi(.cyan),
            underline_ansi(.blue),
            underline_ansi(.magenta),
        };
    };

    pub const high_intensity = struct {
        pub const red = hi_fg_ansi(.red);
        pub const green = hi_fg_ansi(.green);
        pub const yellow = hi_fg_ansi(.yellow);
        pub const blue = hi_fg_ansi(.blue);
        pub const magenta = hi_fg_ansi(.magenta);
        pub const cyan = hi_fg_ansi(.cyan);
        pub const black = hi_fg_ansi(.black);
        pub const white = hi_fg_ansi(.white);

        pub const rainbow = [6][]const u8{
            hi_fg_ansi(.red),
            hi_fg_ansi(.yellow),
            hi_fg_ansi(.green),
            hi_fg_ansi(.cyan),
            hi_fg_ansi(.blue),
            hi_fg_ansi(.magenta),
        };

        pub const bold = struct {
            pub const red = hi_bold_ansi(.red);
            pub const green = hi_bold_ansi(.green);
            pub const yellow = hi_bold_ansi(.yellow);
            pub const blue = hi_bold_ansi(.blue);
            pub const magenta = hi_bold_ansi(.magenta);
            pub const cyan = hi_bold_ansi(.cyan);
            pub const black = hi_bold_ansi(.black);
            pub const white = hi_bold_ansi(.white);

            pub const rainbow = [6][]const u8{
                hi_bold_ansi(.red),
                hi_bold_ansi(.yellow),
                hi_bold_ansi(.green),
                hi_bold_ansi(.cyan),
                hi_bold_ansi(.blue),
                hi_bold_ansi(.magenta),
            };

            pub const underline = struct {
                pub const red = hi_bold_underline_ansi(.red);
                pub const green = hi_bold_underline_ansi(.green);
                pub const yellow = hi_bold_underline_ansi(.yellow);
                pub const blue = hi_bold_underline_ansi(.blue);
                pub const magenta = hi_bold_underline_ansi(.magenta);
                pub const cyan = hi_bold_underline_ansi(.cyan);
                pub const black = hi_bold_underline_ansi(.black);
                pub const white = hi_bold_underline_ansi(.white);

                pub const rainbow = [6][]const u8{
                    hi_bold_underline_ansi(.red),
                    hi_bold_underline_ansi(.yellow),
                    hi_bold_underline_ansi(.green),
                    hi_bold_underline_ansi(.cyan),
                    hi_bold_underline_ansi(.blue),
                    hi_bold_underline_ansi(.magenta),
                };
            };
        };
    };
};

pub const bg = struct {
    pub const red = bg_ansi(.red);
    pub const green = bg_ansi(.green);
    pub const yellow = bg_ansi(.yellow);
    pub const blue = bg_ansi(.blue);
    pub const magenta = bg_ansi(.magenta);
    pub const cyan = bg_ansi(.cyan);
    pub const black = bg_ansi(.black);
    pub const white = bg_ansi(.white);

    pub const rainbow = [6][]const u8{
        bg_ansi(.red),
        bg_ansi(.yellow),
        bg_ansi(.green),
        bg_ansi(.cyan),
        bg_ansi(.blue),
        bg_ansi(.magenta),
    };

    pub const high_intensity = struct {
        pub const red = hi_bg_ansi(.red);
        pub const green = hi_bg_ansi(.green);
        pub const yellow = hi_bg_ansi(.yellow);
        pub const blue = hi_bg_ansi(.blue);
        pub const magenta = hi_bg_ansi(.magenta);
        pub const cyan = hi_bg_ansi(.cyan);
        pub const black = hi_bg_ansi(.black);
        pub const white = hi_bg_ansi(.white);

        pub const rainbow = [6][]const u8{
            hi_bg_ansi(.red),
            hi_bg_ansi(.yellow),
            hi_bg_ansi(.green),
            hi_bg_ansi(.cyan),
            hi_bg_ansi(.blue),
            hi_bg_ansi(.magenta),
        };
    };
};

pub const reset = "\x1b[0m";
pub const color_reset = "\x1b[0m";

const Color = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,

    fn digit(self: Color) []const u8 {
        const digits = "01234567";
        return digits[@intFromEnum(self)..][0..1];
    }
};

fn fg_ansi(color: Color) []const u8 {
    return "\x1b[0;3" ++ color.digit() ++ "m";
}

fn hi_fg_ansi(color: Color) []const u8 {
    return "\x1b[0;9" ++ color.digit() ++ "m";
}

fn bold_ansi(color: Color) []const u8 {
    return "\x1b[1;3" ++ color.digit() ++ "m";
}

fn hi_bold_ansi(color: Color) []const u8 {
    return "\x1b[1;9" ++ color.digit() ++ "m";
}

fn underline_ansi(color: Color) []const u8 {
    return "\x1b[4;3" ++ color.digit() ++ "m";
}

fn hi_underline_ansi(color: Color) []const u8 {
    return "\x1b[4;9" ++ color.digit() ++ "m";
}

fn bold_underline_ansi(color: Color) []const u8 {
    return "\x1b[1;4;3" ++ color.digit() ++ "m";
}

fn hi_bold_underline_ansi(color: Color) []const u8 {
    return "\x1b[1;4;9" ++ color.digit() ++ "m";
}

fn bg_ansi(color: Color) []const u8 {
    return "\x1b[4" ++ color.digit() ++ "m";
}

fn hi_bg_ansi(color: Color) []const u8 {
    return "\x1b[10" ++ color.digit() ++ "m";
}
