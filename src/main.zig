const std = @import("std");
const expectEq = std.testing.expectEqual;
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap(usize, void);

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

fn lessThan(comptime ctx: type, l: []const u8, r: []const u8) bool {
    _ = ctx;
    return @ptrToInt(l.ptr) < @ptrToInt(r.ptr);
}

const Bytes = struct {
    slices: ArrayList([]const u8),
    hashset: HashMap,

    const This = @This();

    pub fn antiAlias(this: *This) void {
        // Sort by start of slice
        std.sort.sort([]const u8, this.slices.items, struct {}, lessThan);
        this.merge();
    }

    fn merge(this: *This) void {
        // We assume `this.slices.items` is sorted.
        var i: usize = 0;
        var length: usize = this.slices.items.len;
        while (i < length - 1) {
            var start_0 = @ptrToInt(this.slices.items[i].ptr);
            var end_0 = start_0 + this.slices.items[i].len;
            var start_1 = @ptrToInt(this.slices.items[i + 1].ptr);
            var end_1 = start_1 + this.slices.items[i + 1].len;
            _ = end_1;

            if (start_1 == end_0 + 1) {
                // Both slices are adjacent
                // Maybe merge them
                // A [   ]
                // B      [   ]
                this.slices.items[i].len += this.slices.items[i + 1].len;
                _ = this.slices.swapRemove(i + 1);
                std.sort.insertionSort([]const u8, this.slices.items[i + 1 ..], struct {}, lessThan);
                length -= 1;
                continue;
            } else if (start_0 <= start_1 and end_1 <= end_0) {
                // A [     ]
                // B    [ ]
                _ = this.slices.swapRemove(i + 1);
                std.sort.insertionSort([]const u8, this.slices.items[i + 1 ..], struct {}, lessThan);
                length -= 1;
                continue;
            } else if (start_1 < end_0 and end_0 < end_1) {
                // A [     ]
                // B     [    ]
                this.slices.items[i].len += this.slices.items[i + 1].len - (end_1 - start_0);
                _ = this.slices.swapRemove(i + 1);
                std.sort.insertionSort([]const u8, this.slices.items[i + 1 ..], struct {}, lessThan);
                length -= 1;
                continue;
            } else {
                // A [   ]
                // B         [  ]
                i += 1;
            }
        }
    }
};

// Main entry for data extraction
// We want to ensure that a pointer is passed
// In order not to track copied values smh
pub fn getBytes(v: anytype) Bytes {
    switch (@typeInfo(@TypeOf(v))) {
        .Pointer => {
            var bytes = Bytes{ .slices = ArrayList([]const u8).init(allocator), .hashset = HashMap.init(allocator) };
            getBytesRec(v, &bytes);
            return bytes;
        },
        else => {
            @compileError("Argument is not a pointer");
        },
    }
}

fn getBytesRec(v: anytype, bytes: *Bytes) void {
    const T = @TypeOf(v.*);
    switch (@typeInfo(T)) {
        .Bool => {
            bytes.slices.append(@ptrCast(*[@sizeOf(bool)]u8, v)[0..]) catch {};
        },
        .Int => {
            const bits_nb = @typeInfo(T).Int.bits;
            if (bits_nb % 8 == 0) {
                bytes.slices.append(@ptrCast(*[@sizeOf(T)]u8, v)[0..]) catch {};
            } else {
                const new_bits_nb = ((bits_nb / 8) + 1) * 8;
                const new_type = @Type(std.builtin.TypeInfo{
                    .Int = std.builtin.TypeInfo.Int{
                        .bits = new_bits_nb,
                        .signedness = .unsigned,
                    },
                });
                _ = new_type;
                bytes.slices.append(@ptrCast(*[new_bits_nb / 8]u8, v)[0..]) catch {};
            }
        },
        .Struct => |str| {
            inline for (str.fields) |field| {
                const name = field.name;
                getBytesRec(&@field(v, name), bytes);
            }
        },
        .Pointer => |_| {
            bytes.slices.append(@ptrCast(*[@sizeOf(usize)]u8, v)[0..]) catch {};
            getBytesRec(v.*, bytes);
        },
        .Optional => |_| {
            if (v) |some| {
                getBytesRec(some, bytes);
            }
        },
        .Enum => |enu| {
            bytes.slices.append(@ptrCast(*const [@sizeOf(enu.tag_type)]u8, v)[0..]) catch {};
        },
        else => {},
    }
}

test "Simple Bytes" {
    var a: usize = 5;
    var b = getBytes(&a);
    var peek = b.slices.pop();
    try expectEq(@as(usize, 8), peek.len);
    std.debug.print("\n{any}\n", .{@ptrCast(*align(1) const usize, peek).*});
    a = 4;
    std.debug.print("{any}\n", .{@ptrCast(*align(1) const usize, peek).*});
}

test "Structs" {
    const TestStruct = struct {
        a: usize,
        b: bool,
    };
    var a = TestStruct{ .a = 12, .b = true };
    var b = getBytes(&a);
    var peek = b.slices.items[0];
    std.debug.print("\n{any}\n", .{@ptrCast(*align(1) const usize, peek).*});
    a.a = 69;
    std.debug.print("{any}\n", .{@ptrCast(*align(1) const usize, peek).*});

    peek = b.slices.items[1];
    std.debug.print("{any}\n", .{@ptrCast(*align(1) const bool, peek).*});
    a.b = false;
    std.debug.print("{any}\n", .{@ptrCast(*align(1) const bool, peek).*});

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

    var peek = b.slices.items[2];
    b.antiAlias();
    std.debug.print("\n{any}\n", .{@ptrCast(*align(1) const usize, peek).*});
    a_.b.a = 43;
    std.debug.print("{any}\n", .{@ptrCast(*align(1) const usize, peek).*});
}

test "Enums" {
    {
        const Enu = enum { Yes, No };
        var a = Enu.Yes;
        var b = getBytes(&a);
        try expectEq(@as(usize, 1), b.slices.items.len);

        var peek = b.slices.items[0];

        std.debug.print("\n{any}\n", .{@ptrCast(*align(1) const Enu, peek).*});
        a = Enu.No;
        std.debug.print("{any}\n", .{@ptrCast(*align(1) const Enu, peek).*});
    }
    {
        const Enu = enum { Yes, No };
        var a_ = Enu.Yes;
        var a = &(a_);
        var b = getBytes(&a);
        try expectEq(@as(usize, 2), b.slices.items.len);

        var peek = b.slices.items[1];

        std.debug.print("{any}\n", .{@ptrCast(*align(1) const Enu, peek).*});
        a.* = Enu.No;
        std.debug.print("{any}\n", .{@ptrCast(*align(1) const Enu, peek).*});
    }
}
