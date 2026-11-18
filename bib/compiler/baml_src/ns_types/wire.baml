// port: baml_type/src/wire.rs @ d9be6853b (the parts the frontend uses)

// port: baml_type/src/wire.rs::DepSlot @ d9be6853b
// A slot in an artifact's dependency table. Slot 0 is the artifact's own
// package and is never stored; slot `k >= 1` is `dependencies[k - 1]`.
class DepSlot {
    value: int,

    // port: baml_type/src/wire.rs::DepSlot::is_self @ d9be6853b
    function is_self(self) -> bool throws never {
        self.value == 0
    }

    // port: baml_type/src/wire.rs::DepSlot::of_dependency_index @ d9be6853b
    // The slot for entry `index` of a dependency table.
    function of_dependency_index(index: int) -> DepSlot throws never {
        DepSlot { value: index + 1 }
    }

    // port: baml_type/src/wire.rs::DepSlot::dependency_index @ d9be6853b
    // The dependency-table entry this slot names; null for the own package.
    function dependency_index(self) -> int? throws never {
        if (self.value == 0) {
            null
        } else {
            self.value - 1
        }
    }
}

// port: baml_type/src/wire.rs::DepSlot::SELF @ d9be6853b
// The artifact's own package.
const DEP_SLOT_SELF: DepSlot = DepSlot { value: 0 };

// port: baml_type/src/wire.rs::Locator @ d9be6853b
// One entry of an artifact's dependency table: how the owner reaches the
// package bound to the slot, and what binds it there.
type Locator = LocatorDirect | LocatorPrelude | LocatorTransitive;

// A direct dependency: `edge` in the owner's edge table, bound only to a
// package whose interface payload has `digest` (SHA-256, Rust's `Digest`).
class LocatorDirect {
    edge: string,
    digest: uint8array,
}

// A language package, by identity.
class LocatorPrelude {
    value: root.base.LangPackage,
}

// A transitive root: `edge` in the edge table of the package bound to `via`.
class LocatorTransitive {
    via: DepSlot,
    edge: string,
}

// port: baml_type/src/wire.rs::EdgePath @ d9be6853b
// A package located by the edge names that reach it from an artifact's
// owning package, hop by hop; empty for the owning package itself.
class EdgePath {
    value: string[],
}
