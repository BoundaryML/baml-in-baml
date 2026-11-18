// port: baml_compiler2_hir/src/package.rs::tests @ d9be6853b
//
// Rust's `TestDb` is a fresh `Db` with no stdlib (and so no prelude);
// `TestDb::add_root` is `root.db.add_root`.

test "edges resolve by name and close transitively" {
    let db = Db.new();
    let leaf = root.db.add_root(db, "/leaf", root.base.SourceRootKind.Dependency, "leaf", []);
    let mid = root.db.add_root(
        db,
        "/mid",
        root.base.SourceRootKind.Dependency,
        "mid",
        [root.base.Dependency { name: "leaf", root: leaf }],
    );
    // The same root reached under a different spelling: names are on edges,
    // so the consumer's alias resolves to the one root.
    let app = root.db.add_root(
        db,
        "/app",
        root.base.SourceRootKind.Workspace,
        null,
        [
            root.base.Dependency { name: "middle", root: mid },
            root.base.Dependency { name: "l", root: leaf },
        ],
    );

    assert.equal(dependency_named(db, app, "middle"), mid);
    assert.equal(dependency_named(db, app, "l"), leaf);
    assert.equal(dependency_named(db, app, "mid"), null);
    assert.equal(dependency_named(db, app, "leaf"), null);
    assert.equal(package_dependency_closure(db, app), [mid, leaf]);
    assert.equal(package_dependency_closure(db, leaf), []);
}

test "a path head is root an edge or a plain name" {
    let db = Db.new();
    let lib = root.db.add_root(db, "/lib", root.base.SourceRootKind.Dependency, "lib", []);
    let app = root.db.add_root(
        db,
        "/app",
        root.base.SourceRootKind.Workspace,
        null,
        [root.base.Dependency { name: "util", root: lib }],
    );
    let plain: PathHead = PathHeadPlain {};

    // `root` is the package itself; an edge name is the package it reaches.
    assert.equal(path_head(db, app, [], ["root", "Foo"]), PathHeadPackage { value: app });
    assert.equal(path_head(db, app, [], ["util", "Foo"]), PathHeadPackage { value: lib });
    // A name no edge carries, the dependency's OWN name included, is a plain
    // name of the scope: `Cart.empty` starts at the item `Cart`. A package's
    // own declared name is not an edge either: `lib` spells itself as `root`.
    assert.equal(path_head(db, lib, [], ["lib", "Foo"]), plain);
    assert.equal(path_head(db, lib, [], ["root", "Foo"]), PathHeadPackage { value: lib });
    assert.equal(path_head(db, app, [], ["lib", "Foo"]), plain);
    assert.equal(path_head(db, app, [], ["Cart", "empty"]), plain);
    // A package segment qualifies what follows it; alone, a name is the item
    // of that name, whatever packages are called.
    assert.equal(path_head(db, app, [], ["util"]), plain);
    assert.equal(path_head(db, app, [], ["root"]), plain);
}
