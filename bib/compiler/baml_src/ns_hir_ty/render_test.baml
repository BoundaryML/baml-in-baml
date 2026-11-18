// Viewpoint spellings. render.rs has no `#[cfg(test)]` tests; these guard
// the path rules every type-checker message is spelled with.

// A declaration of `pkg` at `namespace.name`.
function decl(pkg: int, namespace: string[], name: string) -> root.types.DeclName throws never {
    root.types.QualifiedTypeName { pkg: pkg, namespace: namespace, name: name }
}

test "a viewpoint spells declarations as source in its namespace writes them" {
    let db = root.hir.Db.new();
    let lib = root.db.add_root(db, "/lib", root.base.SourceRootKind.Dependency, "lib", []);
    let app = root.db.add_root(
        db,
        "/app",
        root.base.SourceRootKind.Workspace,
        null,
        [root.base.Dependency { name: "util", root: lib }],
    );
    let file = root.db.add_file(db, app, "/app/ns_shop/cart.baml", "class Cart {}");
    let vp = Viewpoint.for_file(db, file);

    assert.equal(vp.namespace, ["shop"]);
    // The viewing namespace is bare, the rest of the package `root.`-qualified.
    assert.equal(vp.path(decl(app, ["shop"], "Cart")), "Cart");
    assert.equal(vp.path(decl(app, [], "Order")), "root.Order");
    assert.equal(vp.path(decl(app, ["billing"], "Invoice")), "root.billing.Invoice");
    // A dependency by the viewer's edge name, not its own name.
    assert.equal(vp.path(decl(lib, ["json"], "Value")), "util.json.Value");
    assert.equal(vp.source_path(decl(lib, [], "Value")), "util.Value");
    assert.equal(vp.package_prefix(app), null);
    assert.equal(vp.package_prefix(lib), "util");
    // Synthetic effect parameters read as `callback` from a viewer.
    assert.equal(vp.type_var("__effect_param_0"), "callback");
    assert.equal(vp.type_var("T"), "T")
}

test "a canonical viewpoint spells every package by its display label" {
    let db = root.hir.Db.new();
    let lib = root.db.add_root(db, "/lib", root.base.SourceRootKind.Dependency, "lib", []);
    let app = root.db.add_root(db, "/app", root.base.SourceRootKind.Workspace, null, []);
    let vp = Viewpoint.canonical(db);

    assert.equal(vp.path(decl(lib, ["json"], "Value")), "lib.json.Value");
    assert.equal(vp.path(decl(app, [], "Order")), "user.Order");
    assert.equal(vp.type_var("__effect_param_0"), "__effect_param_0");
    let unspellable = vp.source_path(decl(lib, [], "Value")) catch (e) {
        Unspellable => "unspellable",
    };
    assert.equal(unspellable, "unspellable")
}

test "types render through the viewpoint" {
    let db = root.hir.Db.new();
    let app = root.db.add_root(db, "/app", root.base.SourceRootKind.Workspace, null, []);
    let vp = Viewpoint.for_namespace(db, app);
    let ty: root.types.Ty = root.types.TyUnion {
        members: [
            root.types.TyList { elem: root.types.TyClass { name: decl(app, [], "Cart"), args: [] } },
            root.types.TyNull {},
        ],
    };

    assert.equal(ty_spell(ty, vp), "Cart[] | null");
    assert.equal(vp.source_text(ty), "Cart[] | null");
    assert.equal(vp.labelled_text(ty), "user.Cart[] | null")
}
