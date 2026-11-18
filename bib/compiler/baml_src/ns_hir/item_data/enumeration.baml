// port: baml_compiler2_hir/src/item_data/enumeration.rs @ d9be6853b
//
// Enumeration queries: "which items does this file declare?". Consumers get a
// list of `*Loc` ids and look each one up with a `*_data` query; they never
// touch the `ItemTree`'s maps or mint a `Loc` themselves. Each list is sorted
// by source position, so iteration order is deterministic.
//
// deviation: the `file_<items>` queries are not memoized (`Memos` has no
// field for them); each call re-sorts the file's items.

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_items @ d9be6853b
// The `file_items!` macro's body: the ids of `items` ordered by source
// position, then name, then id. Companions sit at their parent's offset, so
// ties are broken by a position-independent key.
function file_items<T>(
    items: map<int, T>,
    position: (T) -> (int, string) throws never,
) -> int[] throws never {
    let keyed = items.keys().map((id) -> {
        (id, position(items[id]))
    });
    keyed
        .sort_by((left, right) -> {
            then_with(left.1.0.cmp(right.1.0), () -> {
                then_with(left.1.1.cmp(right.1.1), () -> {
                    left.0.cmp(right.0)
                })
            })
        })
        .map((entry) -> {
            entry.0
        })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_classes @ d9be6853b
// Every class in `file`, in source order.
function file_classes(db: Db, file: int) -> int[] throws never {
    let item_tree = file_item_tree(db, file);
    file_items(item_tree.classes, (item) -> {
        (item.span.start, item.name)
    })
        .map((id) -> {
            db.class_locs.intern(file, id)
        })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_functions @ d9be6853b
// Every function in `file`, in source order (companions beside their
// parent). Includes methods.
function file_functions(db: Db, file: int) -> int[] throws never {
    let item_tree = file_item_tree(db, file);
    file_items(item_tree.functions, (item) -> {
        (item.span.start, item.name)
    })
        .map((id) -> {
            db.function_locs.intern(file, id)
        })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_enums @ d9be6853b
// Every enum declared in `file`, in source order.
function file_enums(db: Db, file: int) -> int[] throws never {
    let item_tree = file_item_tree(db, file);
    file_items(item_tree.enums, (item) -> {
        (item.span.start, item.name)
    })
        .map((id) -> {
            db.enum_locs.intern(file, id)
        })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_interfaces @ d9be6853b
// Every interface declared in `file`, in source order.
function file_interfaces(db: Db, file: int) -> int[] throws never {
    let item_tree = file_item_tree(db, file);
    file_items(item_tree.interfaces, (item) -> {
        (item.span.start, item.name)
    })
        .map((id) -> {
            db.interface_locs.intern(file, id)
        })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_type_aliases @ d9be6853b
// Every type alias in `file`, in source order.
function file_type_aliases(db: Db, file: int) -> int[] throws never {
    let item_tree = file_item_tree(db, file);
    file_items(item_tree.type_aliases, (item) -> {
        (item.span.start, item.name)
    })
        .map((id) -> {
            db.type_alias_locs.intern(file, id)
        })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_lets @ d9be6853b
// Every top-level `let` declared in `file`, in source order.
function file_lets(db: Db, file: int) -> int[] throws never {
    let item_tree = file_item_tree(db, file);
    file_items(item_tree.lets, (item) -> {
        (item.span.start, item.name)
    })
        .map((id) -> {
            db.let_locs.intern(file, id)
        })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::file_impls @ d9be6853b
// Every `implements` block in `file`, in source order, in-body and
// out-of-body. Source order is load-bearing: coherence needs a deterministic
// order to pick a winner among overlapping impls.
function file_impls(db: Db, file: int) -> int[] throws never {
    db.memo.file_impls.get(file, () -> {
        file_item_tree(db, file).impl_order.map((id) -> {
            db.impl_locs.intern(file, id)
        })
    })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::impl_is_for_class @ d9be6853b
// Whether `block` implements for `class_` itself: written in the class's body
// (its recorded owner: identity, never the name), or out-of-body for exactly
// that class (the AST's rule).
function impl_is_for_class(block: ImplBlock, class_id: int, class_: Class) -> bool throws never {
    match (block.origin) {
        root.ast.ImplOrigin.InBody => block.owner == class_id,
        root.ast.ImplOrigin.OutOfBody => {
            root.ast.impl_is_for_class(
                block.origin,
                block.generics.length() == 0,
                block.for_target,
                class_.name,
            )
        },
    }
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::class_impls @ d9be6853b
// The `implements` blocks that are for `class_` itself, in source order.
function class_impls(db: Db, class_: int) -> int[] throws never {
    db.memo.class_impls.get(class_, () -> {
        let loc = db.class_locs.get(class_);
        let item_tree = file_item_tree(db, loc.file);
        let class_data = item_tree.classes[loc.id];
        item_tree.impl_order
            .filter((id) -> {
                impl_is_for_class(item_tree.impls[id], loc.id, class_data)
            })
            .map((id) -> {
                db.impl_locs.intern(loc.file, id)
            })
    })
}

// port: baml_compiler2_hir/src/item_data/enumeration.rs::impl_class @ d9be6853b
// The class `block` is for, when it is for a class of its own file; null for
// a free block.
function impl_class(db: Db, block: int) -> int? throws never {
    let loc = db.impl_locs.get(block);
    let item_tree = file_item_tree(db, loc.file);
    let data = item_tree.impls[loc.id];
    file_classes(db, loc.file).find((class_) -> {
        let class_id = db.class_locs.get(class_).id;
        impl_is_for_class(data, class_id, item_tree.classes[class_id])
    })
}

// needs foundation: `Ordering::then_with`. `ordering`, or `next()` when it is
// `Equal`.
function then_with(
    ordering: baml.ops.Ordering,
    next: () -> baml.ops.Ordering throws never,
) -> baml.ops.Ordering throws never {
    match (ordering) {
        baml.ops.Ordering.Equal => next(),
        _ => ordering,
    }
}
