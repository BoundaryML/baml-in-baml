// port: baml_compiler2_hir/src/loc.rs @ d9be6853b (DeclRef, ItemId)
//
// The seven interned `*Loc` structs are `int`s into the Db's `LocArena`s
// (`db.baml`); their manual `Debug` impls print a fixed `FunctionLoc(..)` and
// have nothing to port.

// port: baml_compiler2_hir/src/loc.rs::DeclRef @ d9be6853b
// A reference to a possibly-external declaration, algebraic over provenance.
// `Source`: the source is available, and this database type-checks it.
// `External`: no source; the declaration is known only through a package
// interface, by a kind-specific interned extern identity `E`. `L` is the
// kind's `*Loc` (an `int`). Every consumer matches both arms.
// deviation: BAML type aliases take no generic parameters, so there is no
// `DeclRef<L, E>` alias: a use site spells the union
// `DeclRefSource<L> | DeclRefExternal<E>`.

// Source available: type-checked by this database.
class DeclRefSource<L> {
    value: L,
}

// Source unavailable: shape known only through a package interface.
class DeclRefExternal<E> {
    value: E,
}

// port: baml_compiler2_hir/src/loc.rs::ItemId @ d9be6853b
// Any top-level item location (an interned loc id of the variant's kind).
type ItemId = ItemIdFunction
    | ItemIdClass
    | ItemIdEnum
    | ItemIdInterface
    | ItemIdTypeAlias
    | ItemIdLet;

class ItemIdFunction {
    value: int,
}

class ItemIdClass {
    value: int,
}

class ItemIdEnum {
    value: int,
}

class ItemIdInterface {
    value: int,
}

class ItemIdTypeAlias {
    value: int,
}

class ItemIdLet {
    value: int,
}

// port: baml_compiler2_hir/src/loc.rs::impl Debug for ItemId @ d9be6853b
function item_id_debug(item: ItemId) -> string throws never {
    match (item) {
        ItemIdFunction => "ItemId::Function(..)",
        ItemIdClass => "ItemId::Class(..)",
        ItemIdEnum => "ItemId::Enum(..)",
        ItemIdInterface => "ItemId::Interface(..)",
        ItemIdTypeAlias => "ItemId::TypeAlias(..)",
        ItemIdLet => "ItemId::Let(..)",
    }
}
