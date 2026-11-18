// port: baml_compiler2_hir_ty/src/llm_output.rs @ d9be6853b
//
// The parts of an LLM function's output a model can never fill. A model
// answers with JSON, so the runtime drops a return-type union member with no
// JSON form (`uint8array | string` asks for a `string`), and an optional
// field of such a type is only ever `null`. These queries run the runtime's
// analysis (`root.types.JsonInhabitance`) on the declared return type, so the
// compiler can warn where the type is written. Only a return type known at
// compile time is analyzed: a generic one, or one that reaches `unknown`, an
// interface, or a declaration served from a package interface, gets no
// findings.
//
// Restructured:
// - The tracked queries are `TrackedMemo`s on `db.ty_memo`
//   (`llm_output_findings` keyed by function loc,
//   `package_always_null_fields` by root id).
// - `CompilerDefs`' `JsonDefs::Error = ()` is the empty class
//   `CompilerDefsError`; JsonDefs's `check` and `shape` have no default
//   bodies (json_inhabit.baml), so `CompilerDefs` writes Rust's defaults.
// - `RuntimeTy::try_from(&Ty)` is `narrow_ty_to_runtime_ty` (its
//   `NarrowError` is Rust's `Err`), `Ty::from(&RuntimeTy)` is
//   `widen_runtime_ty_to_ty`.
// - `Walk`'s `&mut` out-parameters are arrays and sets the methods push to;
//   an `FxHashSet` is a `map<_, bool>`.

// port: baml_compiler2_hir_ty/src/llm_output.rs::LlmOutputFindings @ d9be6853b
// What a model can never return from one LLM function.
class LlmOutputFindings {
    // Each member of the return type the model can never return, and
    // whether that is because it has no values at all (rather than no JSON
    // form). The whole return type when nothing in it can be returned.
    dropped: (root.types.Ty, bool)[],
    // What the model can return instead: the return type without the dropped
    // members. Null when it can return nothing.
    kept: root.types.Ty?,
    // The optional fields, in classes the return type reaches, that the
    // model can never fill, so they are always `null`: each class's name and
    // the field's name. `@skip` fields are not among them.
    always_null: (root.types.DeclName, string)[],

    // port: baml_compiler2_hir_ty/src/llm_output.rs::LlmOutputFindings::default @ d9be6853b
    function default_() -> LlmOutputFindings throws never {
        LlmOutputFindings { dropped: [], kept: null, always_null: [] }
    }
}

// port: baml_compiler2_hir_ty/src/llm_output.rs::llm_output_findings @ d9be6853b
// The findings for `function_`, or none when it is not an LLM function or its
// return type is not known at compile time.
function llm_output_findings(db: root.hir.Db, function_: int) -> LlmOutputFindings throws never {
    db.ty_memo.llm_output_findings.get(db.cycles, function_, () -> {
        if (root.hir.function_llm_meta(db, function_) == null) {
            return LlmOutputFindings.default_();
        }
        let ret = function_signature_with_diagnostics(db, function_).signature.ret;
        let root_ty = root.types.narrow_ty_to_runtime_ty(ret) catch (e) {
            root.types.NarrowError => {
                return LlmOutputFindings.default_();
            },
        };
        let defs = CompilerDefs { db: db };
        let json = root.types.JsonInhabitance.of_all([root_ty], defs, root.types.JsonNaming.Aliased) catch (e) {
            root.types.JsonError<CompilerDefsError> => {
                return LlmOutputFindings.default_();
            },
        };
        let walk = Walk { json: json, defs: defs };
        let findings = LlmOutputFindings.default_();
        if (json.status(root_ty) == root.types.JsonStatus.Json) {
            let kept = walk.kept(root_ty, findings.dropped, {});
            findings.kept = root.types.widen_runtime_ty_to_ty(kept);
            walk.always_null(root_ty, findings.always_null, {});
        } else {
            findings.dropped.push((ret, json.status(root_ty) == root.types.JsonStatus.Empty));
        }
        findings
    })
}

// port: baml_compiler2_hir_ty/src/llm_output.rs::package_always_null_fields @ d9be6853b
// The fields every LLM function in the package `root_id` leaves always
// `null` (`LlmOutputFindings.always_null`), so a class's own file can warn on
// them. Sorted and deduplicated.
function package_always_null_fields(
    db: root.hir.Db,
    root_id: int,
) -> (root.types.DeclName, string)[] throws never {
    db.ty_memo.package_always_null_fields.get(db.cycles, root_id, () -> {
        let fields: (root.types.DeclName, string)[] = [];
        for (let file in db.source_root(root_id).files) {
            for (let function_ in root.hir.file_functions(db, file)) {
                for (let field in llm_output_findings(db, function_).always_null) {
                    fields.push(field);
                }
            }
        }
        fields.sort_by((a, b) -> {
            let by_class = root.types.cmp_decl_name(a.0, b.0);
            if (by_class != baml.ops.Ordering.Equal) {
                by_class
            } else {
                a.1.cmp(b.1)
            }
        });
        let unique: (root.types.DeclName, string)[] = [];
        for (let field in fields) {
            let last = unique.at(unique.length() - 1);
            if (last == null || last != field) {
                unique.push(field);
            }
        }
        unique
    })
}

// port: baml_compiler2_hir_ty/src/llm_output.rs::CompilerDefs @ d9be6853b
// Rust's `JsonDefs::Error = ()`: the analysis stops.
class CompilerDefsError {
}

// port: baml_compiler2_hir_ty/src/llm_output.rs::CompilerDefs @ d9be6853b
// The compiler's declarations as the JSON analysis reads them. A declaration
// served from a package interface has no `@skip` information, so it stops
// the analysis, as do the types whose JSON form only the runtime decides.
class CompilerDefs {
    db: root.hir.Db,

    implements root.types.JsonDefs {
        type Error = CompilerDefsError;

        // port: baml_compiler2_hir_ty/src/llm_output.rs::CompilerDefs::class @ d9be6853b
        function class_(
            self,
            head: root.types.DeclName,
            args: root.types.RuntimeTy[],
        ) -> root.types.JsonClass {
            let class_ = match (class_ref_of(self.db, head)) {
                let r: root.hir.DeclRefSource<int> => r.value,
                _ => {
                    throw CompilerDefsError {}
                },
            };
            let bindings: root.types.TypeBindings = {};
            let frame = class_generic_frame(self.db, class_);
            for (let i = 0; i < frame.length() && i < args.length(); i += 1) {
                bindings.set(frame[i], root.types.widen_runtime_ty_to_ty(args[i]));
            }
            let fields: root.types.JsonField[] = [];
            for (let (let name, let ty, let attrs) in resolve_class_fields(self.db, class_)) {
                let substituted = root.types.substitute_ty(ty, bindings);
                let runtime = root.types.narrow_ty_to_runtime_ty(substituted) catch (e) {
                    root.types.NarrowError => {
                        throw CompilerDefsError {}
                    },
                };
                fields.push(
                    root.types.JsonField {
                        name: name,
                        alias: attrs.schema.alias,
                        skip: attrs.skip,
                        ty: runtime,
                    },
                );
            }
            root.types.JsonClass { fields: fields }
        }

        // port: baml_compiler2_hir_ty/src/llm_output.rs::CompilerDefs::variants @ d9be6853b
        function variants(self, head: root.types.DeclName) -> root.types.JsonVariant[] {
            let enum_loc = match (enum_ref_of(self.db, head)) {
                let r: root.hir.DeclRefSource<int> => r.value,
                _ => {
                    throw CompilerDefsError {}
                },
            };
            root.hir.enum_data(self.db, enum_loc).variants.map((variant) -> {
                root.types.JsonVariant { name: variant.name, skip: variant.attrs.skip }
            })
        }

        // port: baml_compiler2_hir_ty/src/llm_output.rs::CompilerDefs::alias_target @ d9be6853b
        function alias_target(self, head: root.types.DeclName) -> root.types.RuntimeTy {
            let alias = alias_ref_of(self.db, head) ?? throw CompilerDefsError {};
            root.types.narrow_ty_to_runtime_ty(alias_value(self.db, alias)) catch (e) {
                root.types.NarrowError => {
                    throw CompilerDefsError {}
                },
            }
        }

        // port: baml_compiler2_hir_ty/src/llm_output.rs::CompilerDefs::opaque @ d9be6853b
        function opaque(self, ty: root.types.RuntimeTy) -> root.types.JsonStatus {
            match (ty) {
                root.types.TyMedia => root.types.JsonStatus.Json,
                _ => {
                    throw CompilerDefsError {}
                },
            }
        }

        // Rust's default: every type is accepted.
        function check(self, ty: root.types.RuntimeTy) -> void {}

        // Rust's default: no shape.
        function shape(self, ty: root.types.RuntimeTy) -> root.types.RuntimeTy? {
            null
        }
    }
}

// port: baml_compiler2_hir_ty/src/llm_output.rs::Walk @ d9be6853b
class Walk {
    json: root.types.JsonInhabitance,
    defs: CompilerDefs,

    // port: baml_compiler2_hir_ty/src/llm_output.rs::Walk::kept @ d9be6853b
    // `ty`, a `Json` type, without the members a model can never return,
    // which go to `dropped`: each union at the top, under a list or map
    // there, or behind an alias. An alias with nothing dropped keeps its
    // name.
    function kept(
        self,
        ty: root.types.RuntimeTy,
        dropped: (root.types.Ty, bool)[],
        aliases: map<root.types.DeclName, bool>,
    ) -> root.types.RuntimeTy throws never {
        match (ty) {
            let u: root.types.RuntimeTyUnion => {
                let flat: root.types.RuntimeTy[] = [];
                root.types.flatten_union(u.members, flat);
                let kept: root.types.RuntimeTy[] = [];
                for (let member in flat) {
                    let status = self.json.status(member);
                    if (status == root.types.JsonStatus.Json) {
                        kept.push(self.kept(member, dropped, aliases));
                    } else {
                        dropped.push(
                            (
                                root.types.widen_runtime_ty_to_ty(member),
                                status == root.types.JsonStatus.Empty,
                            ),
                        );
                    }
                }
                if (kept.length() == 1) {
                    kept[0]
                } else {
                    root.types.RuntimeTyUnion { members: kept }
                }
            },
            let l: root.types.RuntimeTyList
                if self.json.status(l.elem) == root.types.JsonStatus.Json => {
                root.types.RuntimeTyList { elem: self.kept(l.elem, dropped, aliases) }
            },
            let m: root.types.RuntimeTyMap
                if self.json.status(m.value) == root.types.JsonStatus.Json => {
                root.types.RuntimeTyMap { key: m.key, value: self.kept(m.value, dropped, aliases) }
            },
            let a: root.types.TyTypeAlias if !aliases.has(a.name) => {
                aliases[a.name] = true;
                let before = dropped.length();
                let kept = {
                    let target = self.defs.alias_target(a.name);
                    self.kept(target, dropped, aliases)
                } catch (e) {
                    CompilerDefsError => null,
                };
                aliases.delete(a.name);
                if (kept != null && dropped.length() > before) {
                    kept
                } else {
                    ty
                }
            },
            _ => ty,
        }
    }

    // port: baml_compiler2_hir_ty/src/llm_output.rs::Walk::always_null @ d9be6853b
    // Records in `out` each optional field the model can never fill, in the
    // classes the `Json` parts of `ty` reach. A generic class's field is left
    // out: whether it can be filled depends on the arguments.
    function always_null(
        self,
        ty: root.types.RuntimeTy,
        out: (root.types.DeclName, string)[],
        seen: map<root.types.RuntimeTy, bool>,
    ) -> void throws never {
        if (self.json.status(ty) != root.types.JsonStatus.Json) {
            return;
        }
        match (ty) {
            let u: root.types.RuntimeTyUnion => {
                for (let member in u.members) {
                    self.always_null(member, out, seen);
                }
            },
            let l: root.types.RuntimeTyList => {
                self.always_null(l.elem, out, seen);
            },
            let m: root.types.RuntimeTyMap => {
                self.always_null(m.value, out, seen);
            },
            let a: root.types.TyTypeAlias => {
                if (!seen.has(ty)) {
                    seen[ty] = true;
                    let target = self.defs.alias_target(a.name) catch (e) {
                        CompilerDefsError => null,
                    };
                    if (target != null) {
                        self.always_null(target, out, seen);
                    }
                }
            },
            let c: root.types.RuntimeTyClass => {
                if (seen.has(ty)) {
                    return;
                }
                seen[ty] = true;
                let class_ = self.defs.class_(c.name, c.args) catch (e) {
                    CompilerDefsError => {
                        return;
                    },
                };
                for (let field in class_.fields) {
                    if (field.skip) {
                        continue;
                    }
                    if (c.args.length() == 0 && self.only_null(field.ty, {})) {
                        out.push((c.name, field.name));
                    }
                    self.always_null(field.ty, out, seen);
                }
            },
            _ => {},
        }
    }

    // port: baml_compiler2_hir_ty/src/llm_output.rs::Walk::only_null @ d9be6853b
    // Whether `ty` is optional, but holds nothing else a model can fill:
    // `uint8array?`, or an alias of one. Plain `null` is not: it is only
    // `null` as written.
    function only_null(
        self,
        ty: root.types.RuntimeTy,
        aliases: map<root.types.DeclName, bool>,
    ) -> bool throws never {
        match (ty) {
            let u: root.types.RuntimeTyUnion => {
                let flat: root.types.RuntimeTy[] = [];
                root.types.flatten_union(u.members, flat);
                let non_null = flat.filter((member) -> {
                    !(member is root.types.TyNull)
                });
                non_null.length() < flat.length()
                    && non_null.length() > 0
                    && non_null.every((member) -> {
                        self.json.status(member) != root.types.JsonStatus.Json
                    })
            },
            let a: root.types.TyTypeAlias if !aliases.has(a.name) => {
                aliases[a.name] = true;
                let target = self.defs.alias_target(a.name) catch (e) {
                    CompilerDefsError => null,
                };
                target != null && self.only_null(target, aliases)
            },
            _ => false,
        }
    }
}
