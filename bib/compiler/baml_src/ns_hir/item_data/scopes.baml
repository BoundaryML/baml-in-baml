// port: baml_compiler2_hir/src/item_data/scopes.rs @ d9be6853b
//
// Item <-> scope queries. The builder opens an item's scope in the same step
// that allocates the item, so the link is recorded directly (`Scope.owner`).
//
// deviation: the `<item>_scope` queries are not memoized (`Memos` has no
// field for them); each is two map lookups.

// port: baml_compiler2_hir/src/item_data/scopes.rs::ScopeOwner @ d9be6853b
// The item a scope was opened for, as a `Loc` id.
type ScopeOwner = ScopeOwnerFunction
    | ScopeOwnerClass
    | ScopeOwnerEnum
    | ScopeOwnerInterface
    | ScopeOwnerTypeAlias
    | ScopeOwnerLet
    | ScopeOwnerImpl;

class ScopeOwnerFunction {
    value: int,
}

class ScopeOwnerClass {
    value: int,
}

class ScopeOwnerEnum {
    value: int,
}

class ScopeOwnerInterface {
    value: int,
}

class ScopeOwnerTypeAlias {
    value: int,
}

class ScopeOwnerLet {
    value: int,
}

class ScopeOwnerImpl {
    value: int,
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::scope_owner @ d9be6853b
// The item `scope` was opened for, or null for structural and expression
// scopes (Project/Package/Namespace/File, Block/Lambda/MatchArm/...).
function scope_owner(db: Db, scope: int) -> ScopeOwner? throws never {
    db.memo.scope_owner.get(scope, () -> {
        let key = db.scopes.get(scope);
        let file = key.file;
        match (file_semantic_index(db, file).scope_owner(key.id)) {
            let owner: ItemScopeOwnerFunction => {
                ScopeOwnerFunction { value: db.function_locs.intern(file, owner.value) }
            },
            let owner: ItemScopeOwnerClass => {
                ScopeOwnerClass { value: db.class_locs.intern(file, owner.value) }
            },
            let owner: ItemScopeOwnerEnum => {
                ScopeOwnerEnum { value: db.enum_locs.intern(file, owner.value) }
            },
            let owner: ItemScopeOwnerInterface => {
                ScopeOwnerInterface { value: db.interface_locs.intern(file, owner.value) }
            },
            let owner: ItemScopeOwnerTypeAlias => {
                ScopeOwnerTypeAlias { value: db.type_alias_locs.intern(file, owner.value) }
            },
            let owner: ItemScopeOwnerLet => {
                ScopeOwnerLet { value: db.let_locs.intern(file, owner.value) }
            },
            let owner: ItemScopeOwnerImpl => {
                ScopeOwnerImpl { value: db.impl_locs.intern(file, owner.value) }
            },
            null => null,
        }
    })
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::item_scope @ d9be6853b
// The `item_scope!` macro's body: the scope `owner` opened in `file`, as a
// `ScopeId`.
function item_scope(db: Db, file: int, owner: ItemScopeOwner) -> int? throws never {
    let index = file_semantic_index(db, file);
    let scope = index.item_scope(owner)
        ?? return null;
    index.scope_ids[scope]
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::function_scope @ d9be6853b
// The scope opened for `item`'s body.
function function_scope(db: Db, item: int) -> int? throws never {
    let loc = db.function_locs.get(item);
    item_scope(db, loc.file, ItemScopeOwnerFunction { value: loc.id })
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::class_scope @ d9be6853b
// The scope opened for `item`'s members.
function class_scope(db: Db, item: int) -> int? throws never {
    let loc = db.class_locs.get(item);
    item_scope(db, loc.file, ItemScopeOwnerClass { value: loc.id })
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::interface_scope @ d9be6853b
// The scope opened for `item`'s members.
function interface_scope(db: Db, item: int) -> int? throws never {
    let loc = db.interface_locs.get(item);
    item_scope(db, loc.file, ItemScopeOwnerInterface { value: loc.id })
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::type_alias_scope @ d9be6853b
// The scope opened for `item`'s right-hand side.
function type_alias_scope(db: Db, item: int) -> int? throws never {
    let loc = db.type_alias_locs.get(item);
    item_scope(db, loc.file, ItemScopeOwnerTypeAlias { value: loc.id })
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::let_scope @ d9be6853b
// The scope owning `item`'s initializer.
function let_scope(db: Db, item: int) -> int? throws never {
    let loc = db.let_locs.get(item);
    item_scope(db, loc.file, ItemScopeOwnerLet { value: loc.id })
}

// port: baml_compiler2_hir/src/item_data/scopes.rs::impl_scope @ d9be6853b
// The scope opened for an out-of-body `implement I for T` block's generic
// parameters. Null for blocks without generics: they open no scope.
function impl_scope(db: Db, item: int) -> int? throws never {
    let loc = db.impl_locs.get(item);
    item_scope(db, loc.file, ItemScopeOwnerImpl { value: loc.id })
}
