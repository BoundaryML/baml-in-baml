// port: baml_type/src/int.rs @ d9be6853b
//
// Rust's `Int63` is a BAML `int`: the toolchain's `int` is the same signed
// 63-bit value, and its `<<` / `>>` already wrap and saturate the way
// `shift_left` / `shift_right` spell out bit by bit. The functions below keep
// Rust's contract (a negative count is an `IntShiftError`, not the
// toolchain's panic) and are named `int63_<method>`.
//
// Not ported: `get` (the value itself) and `BIT_MASK` (only the bit-level
// shift used it).

// port: baml_type/src/int.rs::Int63::BITS @ d9be6853b
// Number of bits in a BAML `int`, including its sign bit.
const INT63_BITS: int = 63;

// port: baml_type/src/int.rs::Int63::MIN @ d9be6853b
const INT63_MIN: int = -4611686018427387904;

// port: baml_type/src/int.rs::Int63::MAX @ d9be6853b
const INT63_MAX: int = 4611686018427387903;

// port: baml_type/src/int.rs::IntShiftError @ d9be6853b
// The only invalid shift count in BAML is a negative one; non-negative counts
// at or above the width truncate or saturate. The shifts below name the one
// variant in `throws`: the toolchain reports a one-member alias there as
// extraneous (E0097).
type IntShiftError = IntShiftErrorNegativeCount;

// The shift count was negative.
class IntShiftErrorNegativeCount {
    value: int,
}

// port: baml_type/src/int.rs::Int63::new @ d9be6853b
// `value` as a BAML `int` when it is representable as one. Rust's `i64`
// argument is a `bigint` here: a BAML `int` cannot hold the values outside.
function int63_new(value: bigint) -> int? throws never {
    value.to_int() catch (e) {
        baml.errors.InvalidArgument => null,
    }
}

// port: baml_type/src/int.rs::Int63::shift_left @ d9be6853b
// Shift left modulo the 63-bit width, reading the kept bits as a signed
// two's-complement value; a count of 63 or more gives 0.
function int63_shift_left(value: int, count: int) -> int throws IntShiftErrorNegativeCount {
    if (count < 0) {
        throw IntShiftErrorNegativeCount { value: count }
    }
    value << count
}

// port: baml_type/src/int.rs::Int63::shift_right @ d9be6853b
// Shift right arithmetically, saturating to the sign bit at or above the
// 63-bit width.
function int63_shift_right(value: int, count: int) -> int throws IntShiftErrorNegativeCount {
    if (count < 0) {
        throw IntShiftErrorNegativeCount { value: count }
    }
    value >> count
}
