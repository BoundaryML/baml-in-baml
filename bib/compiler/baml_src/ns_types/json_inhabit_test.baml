// port: baml_type/src/json_inhabit.rs::tests @ d9be6853b
//
// Heads are local DeclNames (`local_decl`, lib_test.baml) and types render
// with `ShortNames` (lib_test.baml), as Rust's `TypeName::local` heads display.
// An analysis error fails the test by propagating, where Rust panics.

// port: baml_type/src/json_inhabit.rs::tests::Defs @ d9be6853b
// Definitions written out by hand: classes by name, each with its fields as
// `(name, skip, type)`, and enums with their variants. The builders are
// `with_class` and `with_enum`: Rust's `class` builder would clash with
// JsonDefs's `class_`, and `enumeration` is renamed to match.
class TestDefs {
    classes: map<DeclName, (string, bool, RuntimeTy)[]>,
    enums: map<DeclName, (string, bool)[]>,

    function new() -> Self {
        TestDefs { classes: {}, enums: {} }
    }

    function with_class(self, name: string, fields: (string, bool, RuntimeTy)[]) -> Self {
        self.classes.set(local_decl(name), fields);
        self
    }

    function with_enum(self, name: string, variants: (string, bool)[]) -> Self {
        self.enums.set(local_decl(name), variants);
        self
    }

    implements JsonDefs {
        type Error = string;

        function class_(self, head: DeclName, args: RuntimeTy[]) -> JsonClass {
            let fields = self.classes.get(head) ?? throw "unknown class";
            JsonClass {
                fields: fields.map((field) -> {
                    JsonField { name: field.0, alias: null, skip: field.1, ty: field.2 }
                }),
            }
        }

        function variants(self, head: DeclName) -> JsonVariant[] {
            let variants = self.enums.get(head) ?? throw "unknown enum";
            variants.map((variant) -> {
                JsonVariant { name: variant.0, skip: variant.1 }
            })
        }

        function alias_target(self, head: DeclName) -> RuntimeTy {
            throw "no aliases here"
        }

        function opaque(self, ty: RuntimeTy) -> JsonStatus {
            match (ty) {
                TyMedia => JsonStatus.Json,
                _ => {
                    throw `\`${render_with(widen_runtime_ty_to_lowering_ty(ty), ShortNames {})}\` has no schema`
                },
            }
        }

        function check(self, ty: RuntimeTy) -> void {}

        function shape(self, ty: RuntimeTy) -> RuntimeTy? {
            null
        }
    }
}

function class_ty(name: string) -> RuntimeTy throws never {
    RuntimeTyClass { name: local_decl(name), args: [] }
}

function status_under(defs: TestDefs, ty: RuntimeTy, naming: JsonNaming) -> JsonStatus {
    JsonInhabitance.of_all([ty], defs, naming).status(ty)
}

function reason_of(defs: TestDefs, ty: RuntimeTy) -> string {
    JsonInhabitance.of_all([ty], defs, JsonNaming.Aliased).witness(ty).reason(ShortNames {})
}

function optional_bytes() -> RuntimeTy throws never {
    RuntimeTyUnion { members: [TyUint8Array {}, TyNull {}] }
}

test "leaves take their own status" {
    let defs = TestDefs.new();
    let cases: (RuntimeTy, JsonStatus)[] = [
        (TyString {}, JsonStatus.Json),
        (TyUint8Array {}, JsonStatus.NoJson),
        (TyNever {}, JsonStatus.Empty),
        (TyMedia { kind: root.base.MediaKind.Image }, JsonStatus.Json),
    ];
    for (let case in cases) {
        assert.equal(status_under(defs, case.0, JsonNaming.Aliased), case.1);
    }
}

test "a union drops what has no json form" {
    let defs = TestDefs.new().with_class("Blob", [("bytes", false, TyUint8Array {})]);
    let cases: (RuntimeTy, JsonStatus)[] = [
        (RuntimeTyUnion { members: [TyUint8Array {}, TyString {}] }, JsonStatus.Json),
        (RuntimeTyUnion { members: [class_ty("Blob"), TyString {}] }, JsonStatus.Json),
        (optional_bytes(), JsonStatus.Json),
        (RuntimeTyUnion { members: [TyNever {}, TyUint8Array {}] }, JsonStatus.NoJson),
        (class_ty("Blob"), JsonStatus.NoJson),
    ];
    for (let case in cases) {
        assert.equal(status_under(defs, case.0, JsonNaming.Aliased), case.1);
    }
}

test "a container of nothing is only the empty one" {
    let defs = TestDefs.new().with_class("Holds", [("nothing", false, TyNever {})]);
    let cases: (RuntimeTy, JsonStatus)[] = [
        (RuntimeTyList { elem: TyNever {} }, JsonStatus.Json),
        (RuntimeTyMap { key: TyString {}, value: TyNever {} }, JsonStatus.Json),
        (RuntimeTyList { elem: class_ty("Holds") }, JsonStatus.Json),
        (class_ty("Holds"), JsonStatus.Empty),
        (RuntimeTyList { elem: TyUint8Array {} }, JsonStatus.NoJson),
    ];
    for (let case in cases) {
        assert.equal(status_under(defs, case.0, JsonNaming.Aliased), case.1);
    }
}

test "a class needs a finite value" {
    let defs = TestDefs.new().with_class("Loop", [("next", false, class_ty("Loop"))]).with_class(
        "Chain",
        [("next", false, RuntimeTyUnion { members: [class_ty("Chain"), TyNull {}] })],
    );
    assert.equal(status_under(defs, class_ty("Loop"), JsonNaming.Aliased), JsonStatus.NoJson);
    assert.equal(status_under(defs, class_ty("Chain"), JsonNaming.Aliased), JsonStatus.Json);
    assert.equal(
        reason_of(defs, class_ty("Loop")),
        "field `Loop.next`: every value of `Loop` is cyclic",
    )
}

test "a skipped field needs an empty value only when json leaves it out" {
    let defs = TestDefs.new()
        .with_class("Tagged", [("name", false, TyString {}), ("kind", true, TyType {})])
        .with_class("Fillable", [("name", false, TyString {}), ("raw", true, TyUint8Array {})]);
    assert.equal(status_under(defs, class_ty("Tagged"), JsonNaming.Aliased), JsonStatus.NoJson);
    assert.equal(
        reason_of(defs, class_ty("Tagged")),
        "field `Tagged.kind` is `@skip`, so JSON leaves it out, and its type has no empty value to hold",
    );
    assert.equal(status_under(defs, class_ty("Tagged"), JsonNaming.Declared), JsonStatus.NoJson);
    assert.equal(status_under(defs, class_ty("Fillable"), JsonNaming.Aliased), JsonStatus.Json);
    assert.equal(status_under(defs, class_ty("Fillable"), JsonNaming.Declared), JsonStatus.NoJson)
}

test "an enum needs a variant the naming shows" {
    let defs = TestDefs.new().with_enum("None", []).with_enum("Hidden", [("A", true)]).with_enum(
        "Shown",
        [("A", true), ("B", false)],
    );
    let enumeration = (name: string) -> RuntimeTy {
        TyEnum { name: local_decl(name) }
    };
    assert.equal(status_under(defs, enumeration("None"), JsonNaming.Aliased), JsonStatus.Empty);
    assert.equal(status_under(defs, enumeration("Hidden"), JsonNaming.Aliased), JsonStatus.NoJson);
    assert.equal(status_under(defs, enumeration("Hidden"), JsonNaming.Declared), JsonStatus.Json);
    assert.equal(status_under(defs, enumeration("Shown"), JsonNaming.Aliased), JsonStatus.Json)
}

test "a reader error carries the fields that lead to it" {
    let defs = TestDefs.new().with_class("Outer", [("inner", false, class_ty("Inner"))]).with_class(
        "Inner",
        [("bytes", false, TyUint8Array {}), ("value", false, TyUnknown {})],
    );
    let ty = RuntimeTyUnion { members: [class_ty("Outer"), TyString {}] };
    let error = {
        JsonInhabitance.of_all([ty], defs, JsonNaming.Aliased);
        null
    } catch (e) {
        let j: JsonError<string> => j,
    };
    assert.equal(error?.error, "`unknown` has no schema");
    assert.equal(error?.path, ["inner", "value"])
}

test "empty values follow the rule the vm builds them by" {
    let defs = TestDefs.new().with_class("Fills", [("n", false, TyInt {})]).with_class(
        "Recurs",
        [("me", false, class_ty("Recurs"))],
    );
    let cases: (RuntimeTy, bool)[] = [
        (RuntimeTyUnion { members: [TyType {}, TyNull {}] }, true),
        (RuntimeTyList { elem: TyNever {} }, true),
        (TyType {}, false),
        (TyNever {}, false),
        (class_ty("Fills"), true),
        (class_ty("Recurs"), false),
    ];
    for (let case in cases) {
        assert.equal(has_empty_value(defs, case.0), case.1);
    }
}
