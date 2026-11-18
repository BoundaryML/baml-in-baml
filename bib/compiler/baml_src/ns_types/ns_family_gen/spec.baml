// port: baml_type/src/family.rs @ d9be6853b (the `ty_family!` invocation)
//
// The master description of the type family. Every declaration in
// ../family.baml is derived from FAMILY by gen.baml.

// port: the `axes { .. }` section.
enum Axis {
    Concrete,
    Abstract,
    Literal,
    Never,
    Typevar,
    Projection,
    Lower,
    Infer,
    Error,
    Special,
    Frame,
}

// What a field holds. `Child`/`Children` are nested types and `Satellite`/
// `Satellites` nested satellite structs: all four are retargeted per member.
// `Head` is the nominal type head `N`, typed as the member's head. `Opaque`
// is copied as is, typed as `Field.of`.
enum FieldKind {
    Child,
    Children,
    Head,
    Satellite,
    Satellites,
    Opaque,
}

class Field {
    name: string,
    kind: FieldKind,
    // The BAML type of an `Opaque` field, or the satellite a `Satellite(s)`
    // field holds; empty otherwise.
    of: string,
}

class Variant {
    name: string,
    axis: Axis,
    fields: Field[],

    // Whether the variant holds a nested type (directly or in a satellite).
    function nests(self) -> bool {
        self.fields.some((f) -> {
            f.kind == FieldKind.Child
                || f.kind == FieldKind.Children
                || f.kind == FieldKind.Satellite
                || f.kind == FieldKind.Satellites
        })
    }

    function has_head(self) -> bool {
        self.fields.some((f) -> {
            f.kind == FieldKind.Head
        })
    }
}

// port: a `satellite Name<N> { .. }` section: a struct threaded per member
// (`FunctionParamTy`, `RuntimeFunctionParamTy`, ...).
class Satellite {
    name: string,
    fields: Field[],
}

// port: a `type Name { includes: [..], child: C, head: H }` section.
class Member {
    name: string,
    // Function-name stem (`narrow_ty_to_runtime_ty`).
    snake: string,
    // The type a nominal head (`N`) is.
    head: string,
    axes: Axis[],
    // The member nested positions hold: the member itself (deep) or another
    // deep member (shallow). Ignored when `interned`.
    child: string,
    // `child: interned(..)`: nested positions are `int` handles into the
    // hash-cons pool.
    interned: bool,
}

class Family {
    variants: Variant[],
    satellites: Satellite[],
    members: Member[],
}

function child(name: string) -> Field {
    Field { name: name, kind: FieldKind.Child, of: "" }
}

function children(name: string) -> Field {
    Field { name: name, kind: FieldKind.Children, of: "" }
}

function head(name: string) -> Field {
    Field { name: name, kind: FieldKind.Head, of: "" }
}

function opaque(name: string, of: string) -> Field {
    Field { name: name, kind: FieldKind.Opaque, of: of }
}

function satellite(name: string, of: string) -> Field {
    Field { name: name, kind: FieldKind.Satellite, of: of }
}

function satellites(name: string, of: string) -> Field {
    Field { name: name, kind: FieldKind.Satellites, of: of }
}

function leaf(name: string, axis: Axis) -> Variant {
    Variant { name: name, axis: axis, fields: [] }
}

const TY_AXES: Axis[] = [
    Axis.Concrete,
    Axis.Abstract,
    Axis.Literal,
    Axis.Never,
    Axis.Typevar,
    Axis.Projection,
    Axis.Error,
    Axis.Special,
];

// Every member is headed by `DeclName`: the frontend (HIR through emit) uses
// each member at `DeclName`; `TypeName` heads appear only on the runtime side.
// A member needed at another head is another entry here.
const FAMILY: Family = Family {
    variants: [
        leaf("Int", Axis.Concrete),
        leaf("Bigint", Axis.Concrete),
        leaf("Float", Axis.Concrete),
        leaf("String", Axis.Concrete),
        leaf("Bool", Axis.Concrete),
        leaf("Null", Axis.Concrete),
        leaf("Uint8Array", Axis.Concrete),
        Variant {
            name: "Media",
            axis: Axis.Concrete,
            fields: [opaque("kind", "root.base.MediaKind")],
        },
        Variant {
            name: "Literal",
            axis: Axis.Literal,
            fields: [opaque("value", "root.base.Literal"), opaque("freshness", "Freshness")],
        },
        Variant { name: "Class", axis: Axis.Concrete, fields: [head("name"), children("args")] },
        Variant {
            name: "Interface",
            axis: Axis.Abstract,
            fields: [head("name"), children("args"), satellites("associated_types", "AssociatedType")],
        },
        Variant { name: "Enum", axis: Axis.Concrete, fields: [head("name")] },
        Variant {
            name: "EnumVariant",
            axis: Axis.Literal,
            fields: [head("name"), opaque("variant", "string")],
        },
        Variant { name: "List", axis: Axis.Concrete, fields: [child("elem")] },
        Variant { name: "Map", axis: Axis.Concrete, fields: [child("key"), child("value")] },
        Variant { name: "Union", axis: Axis.Abstract, fields: [children("members")] },
        Variant {
            name: "Function",
            axis: Axis.Concrete,
            fields: [satellites("params", "FunctionParamTy"), child("ret"), child("throws_")],
        },
        Variant { name: "Future", axis: Axis.Concrete, fields: [child("value"), child("error")] },
        leaf("RustType", Axis.Concrete),
        leaf("Type", Axis.Concrete),
        leaf("Resource", Axis.Concrete),
        leaf("PromptAst", Axis.Concrete),
        Variant { name: "TypeAlias", axis: Axis.Special, fields: [head("name")] },
        Variant { name: "TypeVar", axis: Axis.Typevar, fields: [opaque("param", "ParamTy")] },
        Variant {
            name: "AssociatedTypeProjection",
            axis: Axis.Projection,
            fields: [
                child("base"),
                satellite("interface_", "InterfaceConstraint"),
                opaque("member", "string"),
            ],
        },
        leaf("Unknown", Axis.Abstract),
        leaf("Never", Axis.Never),
        leaf("Error", Axis.Error),
        leaf("Infer", Axis.Lower),
        Variant { name: "TypeArgRef", axis: Axis.Frame, fields: [opaque("index", "int")] },
        Variant { name: "InferVar", axis: Axis.Infer, fields: [opaque("var", "int")] },
        Variant { name: "Tuple", axis: Axis.Concrete, fields: [children("items")] },
    ],
    satellites: [
        Satellite {
            name: "FunctionParamTy",
            fields: [opaque("name", "string?"), child("ty"), opaque("mode", "FunctionParamMode")],
        },
        // Rust's `Interface` satellite: an interface constraint, distinct from
        // the `Interface` existential variant. Renamed because a member's
        // satellite and variant classes share one namespace here
        // (`TyTemplate` + `Interface` would be both).
        Satellite {
            name: "InterfaceConstraint",
            fields: [head("name"), children("generics"), satellites("associated_types", "AssociatedType")],
        },
        // Rust spells an associated-type binding as a `(Name, Ty)` pair; a
        // tuple is not hashable in BAML, and the pool hashes its entries.
        Satellite { name: "AssociatedType", fields: [opaque("name", "string"), child("ty")] },
    ],
    members: [
        Member {
            name: "Ty",
            snake: "ty",
            head: "DeclName",
            axes: TY_AXES,
            child: "Ty",
            interned: false,
        },
        Member {
            name: "LoweringTy",
            snake: "lowering_ty",
            head: "DeclName",
            axes: TY_AXES.concat([Axis.Lower]),
            child: "LoweringTy",
            interned: false,
        },
        Member {
            name: "RuntimeTy",
            snake: "runtime_ty",
            head: "DeclName",
            axes: [
                Axis.Concrete,
                Axis.Abstract,
                Axis.Literal,
                Axis.Never,
                Axis.Typevar,
                Axis.Projection,
                Axis.Special,
            ],
            child: "RuntimeTy",
            interned: false,
        },
        Member {
            name: "CodegenTy",
            snake: "codegen_ty",
            head: "DeclName",
            axes: [Axis.Concrete, Axis.Abstract, Axis.Literal, Axis.Never, Axis.Typevar, Axis.Special],
            child: "CodegenTy",
            interned: false,
        },
        Member {
            name: "RealizedTy",
            snake: "realized_ty",
            head: "DeclName",
            axes: [Axis.Concrete, Axis.Abstract, Axis.Literal, Axis.Never, Axis.Special],
            child: "RealizedTy",
            interned: false,
        },
        Member {
            name: "ConcreteTy",
            snake: "concrete_ty",
            head: "DeclName",
            axes: [Axis.Concrete, Axis.Never],
            child: "RuntimeTy",
            interned: false,
        },
        Member {
            name: "ConcreteRealizedTy",
            snake: "concrete_realized_ty",
            head: "DeclName",
            axes: [Axis.Concrete, Axis.Never],
            child: "RealizedTy",
            interned: false,
        },
        Member {
            name: "TyTemplate",
            snake: "ty_template",
            head: "DeclName",
            axes: [
                Axis.Concrete,
                Axis.Abstract,
                Axis.Literal,
                Axis.Never,
                Axis.Projection,
                Axis.Special,
                Axis.Frame,
            ],
            child: "TyTemplate",
            interned: false,
        },
        Member {
            name: "InferTy",
            snake: "infer_ty",
            head: "DeclName",
            axes: [
                Axis.Concrete,
                Axis.Abstract,
                Axis.Literal,
                Axis.Never,
                Axis.Typevar,
                Axis.Projection,
                Axis.Infer,
                Axis.Error,
                Axis.Special,
            ],
            child: "InferTy",
            interned: true,
        },
    ],
};
