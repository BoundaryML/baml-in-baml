// port: baml_compiler2_hir_ty/src/render.rs @ d9be6853b
//
// Spelling compile-time types from a viewpoint. A `DeclName` carries the
// declaring root, not a name, so nothing renders it without a viewpoint: the
// root looking and the names it reaches other roots by. Every other renderer
// of compile-time types implements `root.types.TyRenderStrategy` with its own
// policy.
//
// Restructured:
// - Rust's `Result<_, NoEdge>` / `Result<_, Unspellable>` are `throws`.
// - `Cow` borrows are plain strings and arrays.
// - The `Spell` trait is a free function per implementor that does more than
//   forward: `ty_spell` (a `Ty` renders through its `LoweringTy` upcast) and
//   `interface_spell`. `impl Spell for DeclName` is `vp.path(decl)` and
//   `impl Spell for LoweringTy` is `root.types.render_with(ty, vp)`, written
//   at the call site; the `&T` / `Box<T>` impls have no counterpart.
//
// Not ported: `display_label` (`display_package` as a `Name`) and the
// `viewer` accessor (read the field).

// port: baml_compiler2_hir_ty/src/render.rs::Viewpoint @ d9be6853b
// A viewpoint: the root looking (when there is one), the namespace in it
// that is looking, and the names it reaches its dependencies by.
//
// Rendering user-facing (a viewer is set) spells a declaration as source in
// the viewer's namespace writes it: a declaration of that namespace bare, any
// other declaration of the viewer's package `root.`-qualified, every
// dependency by the viewer's edge name for it, a declaration a dependency
// re-exports by the path the re-export gives it, and a package the viewer has
// no edge to by its display label (`display_package`); synthetic effect
// parameters show as `callback`. Rendering canonically (no viewer) spells
// every package by its display label and every parameter verbatim.
class Viewpoint {
    viewer: int?,
    // The namespace of the viewer's package that is looking: empty for the
    // package's root namespace, which is also the view when no file is
    // looking.
    namespace: string[],
    // The viewer's edge table (`root.hir.edge_table`): every package it
    // reaches, by the name it reaches it under; empty without a viewer.
    edges: (string, int)[],
    // The database the roots live in.
    db: root.hir.Db,

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::for_namespace @ d9be6853b
    // Also `Viewpoint::user_facing`, which is this with the default
    // namespace: user-facing rendering as seen from `namespace` of `viewer`'s
    // package; with no namespace, from its root namespace (the view of a
    // reader addressing the package as a whole).
    function for_namespace(db: root.hir.Db, viewer: int, namespace: string[] = []) -> Viewpoint throws never {
        Viewpoint { viewer: viewer, namespace: namespace, edges: root.hir.edge_table(db, viewer), db: db }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::for_file @ d9be6853b
    // User-facing rendering as seen from `file`: its package and its
    // namespace. The viewpoint of a diagnostic reported in `file`.
    function for_file(db: root.hir.Db, file: int) -> Viewpoint throws never {
        let package = root.hir.file_package(db, file);
        Viewpoint.for_namespace(db, package.root_id, namespace = package.namespace_path)
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::canonical @ d9be6853b
    // Canonical rendering: every package spelled by its display label,
    // nothing elided.
    function canonical(db: root.hir.Db) -> Viewpoint throws never {
        Viewpoint { viewer: null, namespace: [], edges: [], db: db }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::own_path @ d9be6853b
    // The path of a declaration of the viewer's own package: bare when it
    // belongs to the viewing namespace, else `root.<ns>.<Name>`.
    function own_path(self, decl: root.types.DeclName) -> string throws never {
        if (decl.namespace == self.namespace) {
            decl.name
        } else {
            join_path(root.hir.ROOT_SEGMENT, decl)
        }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::edge_name @ d9be6853b
    // The name the viewer reaches `root_id` by, if it has an edge to it.
    function edge_name(self, root_id: int) -> string? throws never {
        self.edges
            .find((edge) -> {
                edge.1 == root_id
            })
            ?.0
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::package_segment @ d9be6853b
    // The package segment of a path into `root_id` from this viewpoint: null
    // inside the viewer's own package, the viewer's edge name where it has one
    // (unless an item of the viewing namespace is spelled like that edge, in
    // which case the package is out of reach from here); with no viewer at
    // all, the package's display label. Throws `NoEdge` for a package a viewer
    // reaches no other way. Rust's four-arm match on `(edge_name, viewer)` is
    // written as ifs.
    function package_segment(self, root_id: int) -> string? throws NoEdge {
        if (self.viewer == root_id) {
            return null;
        }
        let name = self.edge_name(root_id);
        if (name != null) {
            if (self.viewer != null && self.edge_is_shadowed(name)) {
                throw NoEdge {};
            }
            return name;
        }
        if (self.viewer != null) {
            throw NoEdge {};
        }
        self.display_package(root_id)
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::edge_is_shadowed @ d9be6853b
    // Whether an item of the viewing namespace is spelled like the viewer's
    // edge `name`: source there reads the name as the item, so the edge is out
    // of reach.
    function edge_is_shadowed(self, name: string) -> bool throws never {
        let viewer = self.viewer;
        viewer != null && root.hir.namespace_declares(self.db, viewer, self.namespace, name)
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::source_path @ d9be6853b
    // The dotted path of `decl` as source in the viewer's namespace writes it.
    // Throws `Unspellable` when the viewer reaches the declaration no such
    // way, and for every declaration when no viewer is looking.
    function source_path(self, decl: root.types.DeclName) -> string throws Unspellable {
        if (self.viewer == null) {
            throw Unspellable { value: decl };
        }
        let package = self.package_segment(decl.pkg) catch (e) {
            NoEdge => {
                let reexported = self.reexport_path(decl);
                if (reexported == null) {
                    throw Unspellable { value: decl };
                }
                return reexported;
            },
        };
        if (package == null) {
            self.own_path(decl)
        } else {
            join_path(package, decl)
        }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::reexport_path @ d9be6853b
    // The path a re-export reachable through one of the viewer's edges gives
    // `decl`, if any: `edge.ns.Name` as the re-export spells it. An edge an
    // item of the viewing namespace shadows reaches nothing.
    function reexport_path(self, decl: root.types.DeclName) -> string? throws never {
        for (let edge in self.edges) {
            if (self.edge_is_shadowed(edge.0)) {
                continue;
            }
            let entry = reexport_paths(self.db, edge.1).find((path) -> {
                path.0 == decl
            });
            if (entry != null) {
                return [edge.0].concat(entry.1).concat([entry.2]).join(".");
            }
        }
        null
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::display_package @ d9be6853b
    // A package's display label from this viewpoint (display only, never
    // source): its declared name; an unnamed package shows the name its
    // nearest dependent reaches it by (the last hop of the shortest edge path
    // from the viewer); with no edge path at all, RESERVED_USER_PACKAGE.
    function display_package(self, root_id: int) -> string throws never {
        let own = self.db.source_root(root_id).self_name;
        if (own != null) {
            return own;
        }
        let viewer = self.viewer;
        if (viewer != null) {
            let hops = root.hir.edge_path(self.db, viewer, root_id);
            if (hops != null && hops.length() > 0) {
                return hops[hops.length() - 1].1;
            }
        }
        root.types.RESERVED_USER_PACKAGE
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::wire_head @ d9be6853b
    // A compile-time head packed into a wire name for display: the viewer's
    // own package as `Local`, every other package as a dependency under its
    // display label. Never an identity.
    function wire_head(self, decl: root.types.DeclName) -> root.types.TypeName throws never {
        if (self.viewer == decl.pkg) {
            let pkg: root.types.Package = root.types.PackageLocal {};
            root.types.QualifiedTypeName { pkg: pkg, namespace: decl.namespace, name: decl.name }
        } else {
            self.labelled_head(decl)
        }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::labelled_head @ d9be6853b
    // A compile-time head packed into a wire name with its package always
    // spelled by its display label, the viewer's own included.
    function labelled_head(self, decl: root.types.DeclName) -> root.types.TypeName throws never {
        let pkg: root.types.Package = root.types.PackageDep { value: self.display_package(decl.pkg) };
        root.types.QualifiedTypeName { pkg: pkg, namespace: decl.namespace, name: decl.name }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::labelled_path @ d9be6853b
    // `decl`'s path with its package always spelled by its display label.
    function labelled_path(self, decl: root.types.DeclName) -> string throws never {
        join_path(self.display_package(decl.pkg), decl)
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::labelled_text @ d9be6853b
    // `ty` with every head spelled by `labelled_path`. Display only.
    function labelled_text(self, ty: root.types.Ty) -> string throws never {
        root.types.render_with(root.types.widen_ty_to_lowering_ty(ty), Labelled { viewpoint: self })
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::source_text @ d9be6853b
    // `ty` as source in the viewer's package writes it; throws the first
    // declaration in it that this package cannot name.
    function source_text(self, ty: root.types.Ty) -> string throws Unspellable {
        let strategy = SourceSpelling { viewpoint: self, unspellable: null };
        let text = root.types.render_with(root.types.widen_ty_to_lowering_ty(ty), strategy);
        let unspellable = strategy.unspellable;
        if (unspellable != null) {
            throw Unspellable { value: unspellable };
        }
        text
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::package_prefix @ d9be6853b
    // The package prefix of a path from this viewpoint, for display: null
    // inside the viewer's own package, the edge name for a dependency, and the
    // display name of a package the viewer has no edge to.
    function package_prefix(self, root_id: int) -> string? throws never {
        self.package_segment(root_id) catch (e) {
            NoEdge => self.display_package(root_id),
        }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::Viewpoint::path @ d9be6853b
    // The dotted path of a declaration for display: bare in the viewing
    // namespace, `root.ns.Name` for the rest of the viewer's package,
    // `edge.ns.Name` for a dependency or a re-export, and the display name of
    // a package the viewer reaches no other way.
    function path(self, decl: root.types.DeclName) -> string throws never {
        let package = self.package_segment(decl.pkg) catch (e) {
            NoEdge => {
                return self.reexport_path(decl) ?? join_path(self.display_package(decl.pkg), decl);
            },
        };
        if (package == null) {
            self.own_path(decl)
        } else {
            join_path(package, decl)
        }
    }

    // port: baml_compiler2_hir_ty/src/render.rs::impl TyRenderStrategy for Viewpoint @ d9be6853b
    implements root.types.TyRenderStrategy {
        function qtn(self, qtn: root.types.DeclName) -> string throws never {
            self.path(qtn)
        }

        // A synthetic effect parameter (`__effect_param_N`) shows as
        // `callback` in user-facing output.
        function type_var(self, name: string) -> string throws never {
            if (self.viewer != null && root.types.is_synthetic_effect_param(name)) {
                "callback"
            } else {
                name
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/render.rs::Unspellable @ d9be6853b
// A declaration that source in the viewer's package cannot write: its package
// is neither the viewer nor one of the viewer's edges. The explicit outcome of
// `Viewpoint.source_path`; never spelled by a stand-in.
class Unspellable {
    value: root.types.DeclName,
}

// port: baml_compiler2_hir_ty/src/render.rs::NoEdge @ d9be6853b
// A package the viewer has no edge to: the one outcome of
// `Viewpoint.package_segment` a source path cannot be built from.
class NoEdge {
}

// port: baml_compiler2_hir_ty/src/render.rs::join_path @ d9be6853b
// `package.ns.Name`, or `ns.Name` without a package.
function join_path(package: string?, decl: root.types.DeclName) -> string throws never {
    let head: string[] = if (package != null) {
        [package]
    } else {
        []
    };
    head.concat(decl.namespace).concat([decl.name]).join(".")
}

// port: baml_compiler2_hir_ty/src/render.rs::SourceSpelling @ d9be6853b
// The strategy behind `Viewpoint.source_text`: spells every head as source
// would, recording the first head source cannot spell.
class SourceSpelling {
    viewpoint: Viewpoint,
    unspellable: root.types.DeclName?,

    implements root.types.TyRenderStrategy {
        function qtn(self, qtn: root.types.DeclName) -> string throws never {
            self.viewpoint.source_path(qtn) catch (e) {
                let unspellable: Unspellable => {
                    // Record the first one and keep it.
                    if (self.unspellable == null) {
                        self.unspellable = unspellable.value;
                    }
                    self.viewpoint.path(qtn)
                },
            }
        }

        function type_var(self, name: string) -> string throws never {
            self.viewpoint.type_var(name)
        }
    }
}

// port: baml_compiler2_hir_ty/src/render.rs::Labelled @ d9be6853b
// The strategy behind `Viewpoint.labelled_text`: every head by
// `Viewpoint.labelled_path`.
class Labelled {
    viewpoint: Viewpoint,

    implements root.types.TyRenderStrategy {
        function qtn(self, qtn: root.types.DeclName) -> string throws never {
            self.viewpoint.labelled_path(qtn)
        }

        function type_var(self, name: string) -> string throws never {
            self.viewpoint.type_var(name)
        }
    }
}

// port: baml_compiler2_hir_ty/src/render.rs::impl Spell for Ty @ d9be6853b
// `ty` spelled from `vp`, through its `LoweringTy` upcast.
function ty_spell(ty: root.types.Ty, vp: Viewpoint) -> string throws never {
    root.types.render_with(root.types.widen_ty_to_lowering_ty(ty), vp)
}

// port: baml_compiler2_hir_ty/src/render.rs::impl Spell for Interface @ d9be6853b
// An interface constraint spelled as its existential (`Interface::to_ty`).
function interface_spell(constraint: root.types.InterfaceConstraint, vp: Viewpoint) -> string throws never {
    ty_spell(
        root.types.TyInterface {
            name: constraint.name,
            args: constraint.generics,
            associated_types: constraint.associated_types,
        },
        vp,
    )
}
