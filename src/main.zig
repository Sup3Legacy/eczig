const std = @import("std");
const expectEq = std.testing.expectEqual;
const ArrayList = std.ArrayList;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

const EccBackend = struct {};

pub fn ECC(T: type, B: EccBackend) type {
    return struct {
        val: *T,
        var backend = B;
        const This = @This();

        pub fn read(this: *This) *T {
            return this.val;
        }

        pub fn get_total_byte_length(this: *This) usize {
            _ = this;
            return 42;
        }
    };
}

fn getTypeByteLength(T: type) usize {
    switch (@typeInfo(T)) {
        .Type => {
            return 0;
        },
        .Void => {
            return 0;
        },
        .Bool => {
            return @sizeOf(bool);
        },
        .Int => {
            return @sizeOf(T);
        },
    }
    return 0;
}

const Bytes = struct {
    slices: ArrayList([]const u8),
};

// Main entry for data extraction
// We want to ensure that a pointer is passed
// In order not to track copied values smh
pub fn getBytes(v: anytype) Bytes {
    switch (@typeInfo(@TypeOf(v))) {
        .Pointer => {
            var bytes = Bytes{ .slices = ArrayList([]const u8).init(allocator) };
            getBytesRec(v.*, &bytes);
            return bytes;
        },
        else => {
            @compileError("Argument is not a pointer");
        },
    }
}

fn getBytesRec(v: anytype, bytes: *Bytes) void {
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .Bool => {
            getBytesRec(@boolToInt(v), bytes);
        },
        .Int => {
            const bits_nb = @typeInfo(T).Int.bits;
            if (bits_nb % 8 == 0) {
                bytes.slices.append(@bitCast([@sizeOf(T)]u8, v)[0..]) catch {};
            } else {
                const new_bits_nb = ((bits_nb / 8) + 1) * 8;
                const new_type = @Type(std.builtin.TypeInfo{
                    .Int = std.builtin.TypeInfo.Int{
                        .bits = new_bits_nb,
                        .signedness = .unsigned,
                    },
                });
                bytes.slices.append(@bitCast([new_bits_nb / 8]u8, @intCast(new_type, v))[0..]) catch {};
            }
        },
        .Struct => |str| {
            inline for (str.fields) |field| {
                const name = field.name;
                getBytesRec(@field(v, name), bytes);
                //bits.append(@bitCast([@sizeOf(T)]u8, v)[0..]) catch {};
            }
        },
        .Pointer => |_| {
            //const child_type = pointer.child;
            const intp = @ptrToInt(v);
            getBytesRec(intp, bytes);
            getBytesRec(v.*, bytes);
        },
        .Optional => |_| {
            if (v) |some| {
                getBytesRec(some, bytes);
            }
        },
        .Enum => |_| {
            const val = @enumToInt(v);
            getBytesRec(val, bytes);
        },
        else => {},
    }
}

test "Simple Bytes" {
    const a: usize = 5;
    var b = getBytes(&a);
    try expectEq(@as(usize, 8), b.slices.pop().len);
}

test "Structs" {
    const TestStruct = struct {
        a: usize,
        b: bool,
    };
    var a = TestStruct{ .a = 12, .b = true };
    var b = getBytes(&a);
    try expectEq(@as(usize, 2), b.slices.items.len);
}

test "Structs & pointers" {
    const TestStruct0 = struct {
        a: usize,
        b: bool,
    };
    const TestStruct1 = struct {
        a: usize,
        b: *TestStruct0,
    };
    var a = TestStruct0{ .a = 42, .b = true };
    var a_ = TestStruct1{ .a = 69, .b = &a };
    var b = getBytes(&a_);
    try expectEq(@as(usize, 4), b.slices.items.len);
}

test "Enums" {
    {
        const Enu = enum { Yes, No };
        var a = Enu.Yes;
        var b = getBytes(&a);
        try expectEq(@as(usize, 1), b.slices.items.len);
    }
    {
        const Enu = enum { Yes, No };
        var a = &(Enu.Yes);
        var b = getBytes(&a);
        try expectEq(@as(usize, 2), b.slices.items.len);
    }
}
