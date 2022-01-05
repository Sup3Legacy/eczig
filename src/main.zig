const std = @import("std");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

const EccBackend = struct {

};

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
        .Type => {return 0;},
        .Void => {return 0;},
        .Bool => {return @sizeOf(bool);},
        .Int => {return @sizeOf(T);},
    }
    return 0;
}