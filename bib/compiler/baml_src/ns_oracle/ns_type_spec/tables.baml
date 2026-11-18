// port: baml_tests/src/type_spec/tables.rs @ d9be6853b
//
// Recorded-table assertions: `InferenceResult` carries MIR's inputs
// alongside the types (member resolutions, method receivers, path ladders,
// call plans, scoped type bindings, ...); these tests pin each table's
// entries on small bodies, keyed by source snippet.
//
// Restructured:
// - Rust's `make_db()` + `db.file("test.baml", source)` is `test_file`: a
//   new workspace root holding `test.baml` on a stdlib Db. Each test builds
//   its own Db, as in Rust.
// - Sources are ASCII (`test_file` panics otherwise), so a snippet is the
//   character slice of the expression's byte range, as the fixtures harness
//   slices. Rust's `r#"\n...\n"#` sources are backtick strings, which drop
//   the leading and trailing newline (every source line starts at column
//   0, so dedent strips nothing else); that shifts offsets only, and every
//   snippet is sliced from the same string the Db holds.
// - `ty.render_with(&Viewpoint::canonical(&db))` is `ty_spell(ty, vp)`.
// - `matches!` over a `TirTypeError` variant is a type test on its class.
// - Rust's sorted `Vec<(String, String)>` is a tuple array sorted by both
//   fields (`sort_pairs`); `{args:?}` on a `Vec<String>` is
//   `debug_strings`.
// - Assertion messages are dropped (BAML's asserts take none); every
//   asserted condition and expected value is Rust's.

// A new workspace root on `db` holding `source` as `test.baml`.
function test_file(db: root.hir.Db, source: string) -> int throws never {
    if (!source.is_ascii()) {
        baml.sys.panic("tables sources must be ASCII");
    }
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    root.db.add_file(db, workspace, "test.baml", source)
}

// Rust's `Vec<(String, String)>::sort`: by the first field, then the second.
function sort_pairs(pairs: (string, string)[]) -> (string, string)[] throws never {
    pairs.sort_by((a, b) -> {
        let by_first = a.0.cmp(b.0);
        if (by_first != baml.ops.Ordering.Equal) {
            by_first
        } else {
            a.1.cmp(b.1)
        }
    })
}

// Rust's `{:?}` of a `Vec<String>`: `["a", "b"]`.
function debug_strings(items: string[]) -> string throws never {
    let quoted = items.map((item) -> {
        root.base.rust_debug_string(item)
    });
    `[${quoted.join(", ")}]`
}

// port: baml_tests/src/type_spec/tables.rs::member_resolutions @ d9be6853b
// Every recorded member resolution in `source`, as sorted `(snippet, kind)`
// pairs: the snippet is the recorded expression's exact text.
function member_resolutions(source: string) -> (string, string)[] throws never {
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let out: (string, string)[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        for (let expr in result.member_resolutions.keys()) {
            let range = source_map.expr_span(expr);
            out.push((source.slice(range.start, range.end), kind(result.member_resolutions[expr])));
        }
    }
    sort_pairs(out)
}

// port: baml_tests/src/type_spec/tables.rs::kind @ d9be6853b
// The dispatch MODE of a resolution. A class-inherent method spells its
// binding too; an interface method's binding is the separate axis
// `method_receivers` reads.
function kind(resolution: root.hir_ty.MemberResolution) -> string throws never {
    match (resolution) {
        root.hir_ty.MemberResolutionField => "Field",
        root.hir_ty.MemberResolutionVariant => "Variant",
        root.hir_ty.MemberResolutionFree => "Free",
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (method.callee) {
                root.hir_ty.MethodCalleeInherent => {
                    match (method.receiver) {
                        root.hir_ty.Receiver.Bound => "BoundMethod",
                        root.hir_ty.Receiver.Unbound => "UnboundMethod",
                    }
                },
                root.hir_ty.MethodCalleeVirtual<root.types.Ty> => "InterfaceVirtualMethod",
                root.hir_ty.MethodCalleeConcrete<root.types.Ty> => "InterfaceConcreteMethod",
            }
        },
        root.hir_ty.MemberResolutionInterfaceVirtualField<root.types.Ty> => "InterfaceVirtualField",
    }
}

// port: baml_tests/src/type_spec/tables.rs::method_receivers @ d9be6853b
// Every recorded METHOD resolution in `source` with whether the access binds
// its receiver, as sorted `(snippet, "Bound" | "Unbound")` pairs.
function method_receivers(source: string) -> (string, string)[] throws never {
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let out: (string, string)[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        for (let expr in result.member_resolutions.keys()) {
            let method = match (result.member_resolutions[expr]) {
                let m: root.hir_ty.MemberResolutionMethod<root.types.Ty> => m,
                _ => {
                    continue;
                },
            };
            let range = source_map.expr_span(expr);
            let receiver = match (method.receiver) {
                root.hir_ty.Receiver.Bound => "Bound",
                root.hir_ty.Receiver.Unbound => "Unbound",
            };
            out.push((source.slice(range.start, range.end), receiver));
        }
    }
    sort_pairs(out)
}

// port: baml_tests/src/type_spec/tables.rs::records_field_and_bound_method @ d9be6853b
test "records field and bound method" {
    let resolutions = member_resolutions(
        `
            class Person {
                name string
                function get_name(self) -> string throws never {
                    self.name
                }
            }
            function mr_use(p: Person) -> string throws never {
                let n = p.name;
                p.get_name()
            }
        `,
    );
    // field read records Field
    assert.is_true(resolutions.includes(("p.name", "Field")));
    // self field read records Field
    assert.is_true(resolutions.includes(("self.name", "Field")));
    // method callee records BoundMethod at the CALLEE expr
    assert.is_true(resolutions.includes(("p.get_name", "BoundMethod")))
}

// port: baml_tests/src/type_spec/tables.rs::records_free_and_unbound @ d9be6853b
test "records free and unbound" {
    let resolutions = member_resolutions(
        `
            class Counter {
                function magic() -> int throws never {
                    42
                }
            }
            function mr_free(x: int) -> int throws never {
                x
            }
            function mr_calls() -> int throws never {
                let xs = Counter.magic();
                let f = Counter.magic;
                mr_free(1)
            }
        `,
    );
    // direct call records Free at the callee
    assert.is_true(resolutions.includes(("mr_free", "Free")));
    // The call spelling and the value spelling both record the static as
    // UnboundMethod (no receiver; `self` stays a parameter).
    assert.equal(
        resolutions
            .filter((r) -> {
                r.0 == "Counter.magic" && r.1 == "UnboundMethod"
            })
            .length(),
        2,
    )
}

// port: baml_tests/src/type_spec/tables.rs::records_interface_dispatch_modes @ d9be6853b
test "records interface dispatch modes" {
    let resolutions = member_resolutions(
        `
            interface Named {
                name string
                function describe(self) -> string throws never
            }
            class Dog {
                dog_name string
                implements Named {
                    name links dog_name
                    function describe(self) -> string throws never {
                        "dog"
                    }
                }
            }
            function mr_virtual(n: Named) -> string throws never {
                let field = n.name;
                n.describe()
            }
            function mr_concrete(d: Dog) -> string throws never {
                d.describe()
            }
        `,
    );
    // existential field read is virtual
    assert.is_true(resolutions.includes(("n.name", "InterfaceVirtualField")));
    // existential method call is a virtual slot
    assert.is_true(resolutions.includes(("n.describe", "InterfaceVirtualMethod")));
    // An implements-block method is Impl-owned (never a class-inherent
    // method), so a concrete receiver resolves through the impl tier.
    assert.is_true(resolutions.includes(("d.describe", "InterfaceConcreteMethod")))
}

// port: baml_tests/src/type_spec/tables.rs::records_method_binding_axis @ d9be6853b
// The binding axis is independent of the dispatch mode: `recv.m()` binds
// its receiver whether the callee is inherent, a virtual slot, or a
// statically-matched impl; `I.m(recv)` and `(C as I).m(recv)` never do.
test "records method binding axis" {
    let source = `
        interface Counter {
            function start(self) -> int throws never
        }
        class Tally {
            n int
            implements Counter {
                function start(self) -> int throws never {
                    self.n
                }
            }
        }
        function mr_bound(t: Tally, c: Counter) -> int throws never {
            t.start() + c.start()
        }
        function mr_unbound(t: Tally) -> int throws never {
            Counter.start(t) + (Tally as Counter).start(t)
        }
    `;
    let kinds = member_resolutions(source);
    let receivers = method_receivers(source);
    // concrete receiver access is Bound
    assert.is_true(
        kinds.includes(("t.start", "InterfaceConcreteMethod"))
            && receivers.includes(("t.start", "Bound")),
    );
    // existential receiver access is Bound
    assert.is_true(
        kinds.includes(("c.start", "InterfaceVirtualMethod"))
            && receivers.includes(("c.start", "Bound")),
    );
    // interface-qualified access is Unbound
    assert.is_true(
        kinds.includes(("Counter.start", "InterfaceVirtualMethod"))
            && receivers.includes(("Counter.start", "Unbound")),
    );
    // written-qualifier access is Unbound
    assert.is_true(
        receivers.some((r) -> {
            r.0.ends_with("Counter).start") && r.1 == "Unbound"
        }),
    );
    // no access records both bindings
    assert.is_true(
        !receivers.some((r) -> {
            (r.0 == "t.start" || r.0 == "c.start") && r.1 == "Unbound"
        })
            && !receivers.some((r) -> {
                r.0.includes("Counter") && r.1 == "Bound"
            }),
    )
}

// port: baml_tests/src/type_spec/tables.rs::records_variant @ d9be6853b
test "records variant" {
    let resolutions = member_resolutions(
        `
            enum Status {
                Active
                Done
            }
            function mr_variant() -> Status throws never {
                Status.Active
            }
        `,
    );
    // enum variant value records Variant
    assert.is_true(resolutions.includes(("Status.Active", "Variant")))
}

// port: baml_tests/src/type_spec/tables.rs::records_path_ladders @ d9be6853b
test "records path ladders" {
    let source = `
        class City {
            name string
        }
        class Address {
            city City
        }
        class Person {
            address Address
            function home(self) -> City throws never {
                self.address.city
            }
        }
        function mr_chain(p: Person) -> string throws never {
            let city_name = p.address.city.name;
            p.address.city.name
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let ladders: (string, string)[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        for (let expr in result.path_resolutions.keys()) {
            let range = source_map.expr_span(expr);
            let rendered = result.path_resolutions[expr].segments.map((segment) -> {
                let ty = root.hir_ty.ty_spell(segment.ty, vp);
                let resolution = segment.resolution;
                if (resolution != null) {
                    `${ty}/${kind(resolution)}`
                } else {
                    ty
                }
            });
            ladders.push((source.slice(range.start, range.end), rendered.join(" -> ")));
        }
    }
    // Rust's `sort` then `dedup`.
    let deduped: (string, string)[] = [];
    for (let ladder in sort_pairs(ladders)) {
        if (deduped.at(-1) != ladder) {
            deduped.push(ladder);
        }
    }
    // value-rooted chains record per-segment ladders
    assert.equal(
        deduped,
        [
            (
                "p.address.city.name",
                "user.Person -> user.Address/Field -> user.City/Field -> string/Field",
            ),
            ("self.address.city", "user.Person -> user.Address/Field -> user.City/Field"),
        ],
    )
}

// port: baml_tests/src/type_spec/tables.rs::records_call_plans @ d9be6853b
test "records call plans" {
    let source = `
        function cp_id<T>(x: T) -> T throws never {
            x
        }
        function cp_defaults(a: int, b: int = 2) -> int throws never {
            a
        }
        function cp_use() -> int throws never {
            let solved = cp_id(42);
            let named = cp_defaults(b = 5, a = 1);
            cp_defaults(7)
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let plans: string[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        for (let call in result.call_plans.keys()) {
            let plan = result.call_plans[call];
            let range = source_map.expr_span(call);
            let type_args = plan.type_args.map((ty) -> {
                root.hir_ty.ty_spell(ty, vp)
            });
            let bindings = plan.bindings.map((binding) -> {
                match (binding) {
                    let provided: root.hir_ty.ParamBindingProvided => {
                        `provided:${provided.param_index}`
                    },
                    let omitted: root.hir_ty.ParamBindingOmittedDefault => {
                        `default:${omitted.param_index}:${omitted.param_name}`
                    },
                }
            });
            plans.push(
                `${source.slice(range.start, range.end)} | type_args [${type_args.join(", ")}] | bindings [${bindings.join(", ")}]`,
            );
        }
    }
    // call plans record solved instantiations and param-ordered bindings
    assert.equal(
        plans.sort_by((a, b) -> {
            a.cmp(b)
        }),
        [
            "cp_defaults(7) | type_args [] | bindings [provided:0, default:1:b]",
            "cp_defaults(b = 5, a = 1) | type_args [] | bindings [provided:0, provided:1]",
            "cp_id(42) | type_args [int] | bindings [provided:0]",
        ],
    )
}

// port: baml_tests/src/type_spec/tables.rs::static_method_call_uses_owner_then_function_generic_frame @ d9be6853b
test "static method call uses owner then function generic frame" {
    let source = `
        class RtBox<T> {
            value: T,
            function new(value: T) -> RtBox<T> throws never {
                RtBox<T> { value: value }
            }
        }
        function rt_owner_use() -> RtBox<int> throws never {
            RtBox<int>.new(1)
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let seen = false;
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        // the receiver's written owner argument is part of the unbound frame
        assert.is_true(
            !result.diagnostics.some((diag) -> {
                diag.error is root.hir_ty.TirTypeErrorWrongTypeArgArity
            }),
        );
        for (let call in result.call_plans.keys()) {
            let range = source_map.expr_span(call);
            if (source.slice(range.start, range.end) != "RtBox<int>.new(1)") {
                continue;
            }
            let plan = result.call_plans[call];
            seen = true;
            assert.equal(plan.own_offset, 0);
            assert.is_true(
                plan.slots.length() == 1 && root.hir_ty.ty_spell(plan.slots[0].ty, vp) == "int",
            );
            assert.equal(
                plan.type_args.map((ty) -> {
                    root.hir_ty.ty_spell(ty, vp)
                }),
                ["int"],
            );
        }
    }
    // static owner-generic call plan was not recorded
    assert.is_true(seen)
}

// port: baml_tests/src/type_spec/tables.rs::runtime_call_special_contracts_are_narrow_and_diagnostic @ d9be6853b
test "runtime call special contracts are narrow and diagnostic" {
    let source = `
        function sc_id<T>(value: T) -> T throws never { value }
        function sc_contract<F>() -> null throws never { null }

        function sc_bare() -> int throws never {
            let runtime_t = int.type();
            sc_id<runtime_t>(1)
        }
        function sc_ordinary_contract() -> null throws never {
            sc_contract<(string) -> string>()
        }
        function sc_extract(pkg: reflect.Package) -> null {
            let extracted = pkg.get_function<(string) -> string>("root.Target");
            null
        }
        function sc_session(session: reflect.Session) -> null {
            let value = session.eval("1");
            null
        }
        function sc_sealed() -> reflect.Class throws never {
            reflect.Class {}
        }
        function sc_companion() -> baml.Map<string, int> throws never {
            baml.Map {}
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let errors: root.hir_ty.TirTypeError[] = [];
    let extraction_throws: string? = null;
    let session_args: string[]? = null;
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner);
        let result = root.hir_ty.infer_body(db, owner);
        errors
            = errors.concat(
                result.diagnostics.map((diag) -> {
                    diag.error
                }),
            );
        if (source_map == null) {
            continue;
        }
        for (let call in result.call_plans.keys()) {
            let plan = result.call_plans[call];
            let range = source_map.expr_span(call);
            let snippet = source.slice(range.start, range.end);
            if (snippet.starts_with("pkg.get_function")) {
                extraction_throws
                    = match (plan.slots.at(0)?.ty) {
                        let f: root.types.TyFunction => root.hir_ty.ty_spell(f.throws_, vp),
                        _ => null,
                    };
            }
            if (snippet.starts_with("session.eval")) {
                session_args
                    = plan.type_args.map((ty) -> {
                        root.hir_ty.ty_spell(ty, vp)
                    });
            }
        }
    }

    // only the ordinary function type reports missing throws
    assert.equal(
        errors
            .filter((error) -> {
                error is root.hir_ty.TirTypeErrorFunctionTypeMissingThrows
            })
            .length(),
        1,
    );
    assert.is_true(
        errors.some((error) -> {
            match (error) {
                let e: root.hir_ty.TirTypeErrorComputedGenericArgumentRequiresLetType => {
                    e.name == "runtime_t"
                },
                _ => false,
            }
        }),
    );
    assert.is_true(
        errors.some((error) -> {
            match (error) {
                let e: root.hir_ty.TirTypeErrorCannotConstructReflectionKind => {
                    vp.path(e.class_name) == "reflect.Class"
                },
                _ => false,
            }
        }),
    );
    assert.is_true(
        errors.some((error) -> {
            match (error) {
                let e: root.hir_ty.TirTypeErrorCannotConstructBuiltinCompanion => {
                    vp.path(e.class_name) == "baml.Map" && e.companion.builtin == "map"
                },
                _ => false,
            }
        }),
    );
    assert.equal(extraction_throws, "unknown");
    assert.equal(session_args, ["unknown"])
}

// port: baml_tests/src/type_spec/tables.rs::scoped_type_bindings_are_rigid_frame_parameters @ d9be6853b
// The inference tables behind a scoped `type T = ...` binding, which BAML
// cannot observe: the call plan carries the binding's own rigid parameter
// (marked by the scoped index bit) while the name is in scope, and the
// shadowed static class again once the block closes.
test "scoped type bindings are rigid frame parameters" {
    let source = `
        class ScopeT {}
        function scope_id<X>(value: unknown) -> reflect.Type throws never { reflect.Type.of<X>() }
        function scope_use(runtime_t: reflect.Type) -> reflect.Type throws never {
            let inner = {
                let type ScopeT = runtime_t;
                scope_id<ScopeT>(1)
            }
            scope_id<ScopeT>(3)
        }
        function scope_branch(runtime_t: reflect.Type, choose: bool) -> reflect.Type throws never {
            let branch_value = if choose {
                let type ScopeT = runtime_t;
                scope_id<ScopeT>(2)
            } else {
                scope_id<int>(0)
            }
            scope_id<ScopeT>(4)
        }
        function scope_bad() -> null throws never {
            let type Bad = 42;
            null
        }
        function scope_shape_bad(runtime_t: reflect.Type) -> null throws never {
            let type ShapeT = runtime_t;
            let impossible: ShapeT[] = 42
            null
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let saw_inner = false;
    let saw_outer = 0;
    let saw_branch = false;
    let saw_bad_operand = false;
    let saw_static_shape_error = false;
    let diagnostics: root.hir_ty.TirTypeError[] = [];
    // `TypeMismatch { expected, got }` rendering as `expected` and `got`.
    let is_mismatch = (error: root.hir_ty.TirTypeError, expected: string, got: string) -> bool {
        match (error) {
            let e: root.hir_ty.TirTypeErrorTypeMismatch => {
                root.hir_ty.ty_spell(e.expected, vp) == expected
                    && root.hir_ty.ty_spell(e.got, vp) == got
            },
            _ => false,
        }
    };
    // `[ty] if matches!(ty, Ty::TypeVar(param) if param == parameter)`.
    let is_binding_param = (type_args: root.types.Ty[], parameter: root.types.ParamTy) -> bool {
        type_args.length() == 1
            && match (type_args[0]) {
                let v: root.types.TyTypeVar => v.param == parameter,
                _ => false,
            }
    };
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        diagnostics
            = diagnostics.concat(
                result.diagnostics.map((diag) -> {
                    diag.error
                }),
            );
        saw_bad_operand
            = saw_bad_operand
                || result.diagnostics.some((diag) -> {
                    is_mismatch(diag.error, "reflect.TypeView", "42")
                });
        saw_static_shape_error
            = saw_static_shape_error
                || result.diagnostics.some((diag) -> {
                    is_mismatch(diag.error, "ShapeT[]", "42")
                });

        let binding = result.type_bindings.values().find((b) -> {
            b.name == "ScopeT"
        });
        for (let call in result.call_plans.keys()) {
            let plan = result.call_plans[call];
            let range = source_map.expr_span(call);
            let snippet = source.slice(range.start, range.end);
            if (snippet == "scope_id<ScopeT>(1)") {
                let b = binding ?? baml.sys.panic("ScopeT binding recorded");
                saw_inner = true;
                assert.is_true((b.parameter.index & 2147483648) != 0);
                assert.is_true(is_binding_param(plan.type_args, b.parameter));
            }
            if (snippet == "scope_id<ScopeT>(2)") {
                let b = binding ?? baml.sys.panic("branch ScopeT binding recorded");
                saw_branch = true;
                assert.is_true(is_binding_param(plan.type_args, b.parameter));
            }
            if (snippet == "scope_id<ScopeT>(3)" || snippet == "scope_id<ScopeT>(4)") {
                saw_outer += 1;
                assert.is_true(
                    plan.type_args.length() == 1
                        && root.hir_ty.ty_spell(plan.type_args[0], vp) == "user.ScopeT",
                );
            }
        }
    }
    assert.is_true(saw_inner && saw_branch);
    // the static class is restored at both closing braces
    assert.equal(saw_outer, 2);
    // type-binding operand must be checked below `type`
    assert.is_true(saw_bad_operand);
    // a literal is not a value of a rigid scoped type
    assert.is_true(saw_static_shape_error);
    // valid scoped bindings must not create static-only errors
    assert.equal(diagnostics.length(), 2)
}

// port: baml_tests/src/type_spec/tables.rs::infers_parameter_defaults_as_own_root @ d9be6853b
test "infers parameter defaults as own root" {
    let source = `
        function pd_take(a: int, tag: string = "t", n: int = 1 + 2, bad: int = "x") -> int throws never {
            a
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let function_ = root.hir.file_functions(db, file).at(0) ?? baml.sys.panic("one function");
    let owner = root.hir.BodyOwnerIdParameterDefaults { value: function_ };
    let result = root.hir_ty.infer_body(db, owner);
    let defaults = root.hir.function_parameter_defaults(db, function_);
    let rendered: string[] = [];
    for (let index = 0; index < defaults.params.length(); index += 1) {
        let default_ = defaults.params[index]
            ?? continue;
        let expr = default_.expr;
        let found = result.type_of_expr.get(expr);
        let ty = if (found != null) {
            root.hir_ty.ty_spell(found, vp)
        } else {
            "<missing>"
        };
        let mismatch = if (result.type_mismatches.has(expr)) {
            " MISMATCH"
        } else {
            ""
        };
        rendered.push(`${index}: ${ty}${mismatch}`);
    }
    // defaults check against their parameter's declared type
    assert.equal(rendered, ["1: \"t\"", "2: 3", "3: \"x\" MISMATCH"])
}

// port: baml_tests/src/type_spec/tables.rs::call_plan_waits_for_sibling_vars @ d9be6853b
// The finish fixpoint must not commit a bounded var from its ground lowers
// while a sibling var occurring in a DEFERRED lower is still solvable:
// de_eq's T here must wait for ?T_gen = int, giving string | int[].
test "call plan waits for sibling vars" {
    let source = `
        function de_eq<T>(a: T, b: T) -> bool throws never {
            true
        }
        function de_gen<T>(x: T) -> T[] throws string {
            [x]
        }
        function de_probe() -> bool throws never {
            de_eq(de_gen(1) catch (e) {
                string => "caught"
            }, "caught")
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let plans: string[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        for (let call in result.call_plans.keys()) {
            let range = source_map.expr_span(call);
            let snippet = source.slice(range.start, range.end);
            let args = result.call_plans[call].type_args.map((ty) -> {
                root.hir_ty.ty_spell(ty, vp)
            });
            plans.push(`${snippet.split("(")[0]} -> ${debug_strings(args)}`);
        }
    }
    // solver committed a var while a sibling in its deferred lowers was
    // still solvable
    assert.equal(
        plans.sort_by((a, b) -> {
            a.cmp(b)
        }),
        ["de_eq -> [\"string | int[]\"]", "de_gen -> [\"int\"]"],
    )
}

// port: baml_tests/src/type_spec/tables.rs::call_plan_effect_solves_from_deferred_lambda @ d9be6853b
// Goals before solving: E's only REGISTERED bound is the declared-throws
// upper (`throws unknown`), while the lambda argument's `throws never` lower
// rides a deferred sub; draining goals first lands the lower before E
// commits, so E = never.
test "call plan effect solves from deferred lambda" {
    let source = `
        function ir_probe() -> int {
            let it: baml.iter.Iterator<Item = int, Error = never> = baml.iter.ArrayIterator.new([1, 2, 3, 4]);
            it.reduce((a: int, x: int) -> int { a + x }, 0)
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let plans: string[][] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        for (let call in result.call_plans.keys()) {
            let range = source_map.expr_span(call);
            if (!source.slice(range.start, range.end).starts_with("it.reduce")) {
                continue;
            }
            let plan = result.call_plans[call];
            plans.push(
                plan.type_args.slice(plan.own_offset, plan.type_args.length()).map((ty) -> {
                    root.hir_ty.ty_spell(ty, vp)
                }),
            );
        }
    }
    // reduce's own args must solve A = int, E = never
    assert.equal(plans, [["int", "never"]])
}

// port: baml_tests/src/type_spec/tables.rs::assign_target_chain_records @ d9be6853b
// A member/place assignment target types as an ordinary place expression:
// the chain's types and resolutions record, and the field's type is the
// value's expectation.
test "assign target chain records" {
    let resolutions = member_resolutions(
        `
            class FaNode {
                value int
            }
            function fa_probe(n: FaNode) -> int throws never {
                n.value = 5;
                n.value
            }
        `,
    );
    // the assign TARGET and the read both record Field
    assert.equal(
        resolutions
            .filter((r) -> {
                r.0 == "n.value" && r.1 == "Field"
            })
            .length(),
        2,
    )
}

// port: baml_tests/src/type_spec/tables.rs::union_field_access_records_virtual_view @ d9be6853b
// A field access on a UNION receiver whose members all share one realized
// declaring-interface view records InterfaceVirtualField through that view.
test "union field access records virtual view" {
    let resolutions = member_resolutions(
        `
            interface UvHasSound {
                sound string
            }
            class UvCat {
                sound string
                implements UvHasSound {}
            }
            class UvDog {
                sound string
                implements UvHasSound {}
            }
            function uv_probe(animal: UvCat | UvDog) -> string throws never {
                animal.sound
            }
        `,
    );
    // union field access records the shared virtual view
    assert.is_true(resolutions.includes(("animal.sound", "InterfaceVirtualField")))
}

// port: baml_tests/src/type_spec/tables.rs::pattern_ascription_records_written_nominal @ d9be6853b
// Bindings record the WRITTEN pattern type; aliases are nominal by design.
test "pattern ascription records written nominal" {
    let source = `
        function pa_probe() -> int {
            let j: baml.json.json = baml.json.parse("[1, 2, 3]");
            match (j) {
                let arr: baml.json.json[] => arr.length(),
                _ => -1
            }
        }
    `;
    let db = root.stdlib_db();
    let file = test_file(db, source);
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let renders: string[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        let arena = root.hir.owner_body_expr_body(root.hir.body(db, owner))
            ?? continue;
        for (let pat_id = 0; pat_id < arena.patterns.length(); pat_id += 1) {
            let range = source_map.pattern_span(pat_id);
            let ty = result.type_of_pat.get(pat_id);
            if (source.slice(range.start, range.end).starts_with("let arr") && ty != null) {
                renders.push(root.hir_ty.ty_spell(ty, vp));
            }
        }
    }
    // the ascribed binding records the written nominal type
    assert.equal(renders, ["baml.json.json[]"])
}
