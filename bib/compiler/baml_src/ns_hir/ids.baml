// port: baml_compiler2_hir/src/ids.rs @ d9be6853b
//
// Position-independent item identifiers. Rust's `LocalItemId<Marker>` is an
// `int` here: the packed `hash << 16 | index`. The marker types
// (`FunctionMarker`, `ClassMarker`, ...) only tag `LocalItemId`'s type
// parameter in Rust; with the id an `int` they have nothing to tag, so they
// are not ported.

// FNV-1a (32-bit) parameters, for `hash_name` and `hash_impl_key`.
const FNV_OFFSET_BASIS: int = 2166136261;
const FNV_PRIME: int = 16777619;
const U32_MASK: int = 4294967295;
const U16_MASK: int = 65535;
// The byte Rust's `impl Hash for str` writes after a string's bytes.
const STR_HASH_TERMINATOR: int = 255;

// port: baml_compiler2_hir/src/ids.rs::LocalItemId::new @ d9be6853b
// Upper 16 bits: the name hash; lower 16 bits: the collision index.
function local_item_id_new(hash: int, index: int) -> int throws never {
    ((hash & U16_MASK) << 16) | (index & U16_MASK)
}

// port: baml_compiler2_hir/src/ids.rs::impl Debug for LocalItemId @ d9be6853b
// `LocalItemId(0x0000abcd)`: Rust's `{:#010x}`.
function local_item_id_debug(id: int) -> string throws never {
    let digits = "0123456789abcdef";
    let hex = [28, 24, 20, 16, 12, 8, 4, 0].map((shift) -> {
        digits.at((id >> shift) & 15) ?? "0"
    });
    `LocalItemId(0x${hex.join("")})`
}

// port: baml_compiler2_hir/src/ids.rs::hash_name @ d9be6853b
// Hash a name to 16 bits for use in a `LocalItemId`.
// deviation: FNV-1a over the name's UTF-8 bytes, truncated to 16 bits. Rust
// uses `DefaultHasher` (SipHash-1-3), which BAML cannot compute cheaply
// without unsigned 64-bit math. Ids differ from Rust's; their packing and the
// collision-index scheme do not.
function hash_name(name: string) -> int throws never {
    fnv1a(FNV_OFFSET_BASIS, name.to_utf8().to_array()) & U16_MASK
}

// port: baml_compiler2_hir/src/ids.rs::hash_impl_key @ d9be6853b
// Hash an `implements` block's structural identity, its interface-target head
// and for-target head, to 16 bits for use in an impl's `LocalItemId`. Impls
// sharing both heads collide here and are told apart by the collision index.
// deviation: FNV-1a (see `hash_name`). Like Rust's `Hash` for `str`, each
// head's bytes are followed by a 0xFF byte, so ("ab", "c") and ("a", "bc")
// hash apart.
function hash_impl_key(iface_head: string, for_head: string) -> int throws never {
    let bytes = iface_head.to_utf8()
        .to_array()
        .concat([STR_HASH_TERMINATOR])
        .concat(for_head.to_utf8().to_array())
        .concat([STR_HASH_TERMINATOR]);
    fnv1a(FNV_OFFSET_BASIS, bytes) & U16_MASK
}

// One FNV-1a round per byte, kept to 32 bits.
function fnv1a(seed: int, bytes: int[]) -> int throws never {
    bytes.reduce(
        (hash, byte) -> {
            ((hash ^ byte) * FNV_PRIME) & U32_MASK
        },
        seed,
    )
}

// port: baml_compiler2_hir/src/ids.rs::ItemKind @ d9be6853b
// Item kinds for collision tracking in the `ItemTree`.
enum ItemKind {
    Function,
    Class,
    Enum,
    Interface,
    TypeAlias,
    Let,
    Impl,
}
