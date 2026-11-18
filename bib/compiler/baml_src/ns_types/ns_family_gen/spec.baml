// The master description of the type family: the BAML twin of the
// `ty_family!` invocation in baml_type/src/family.rs. Every generated
// declaration in ../family.baml is derived from FAMILY.

enum Axis {
    Concrete,
    Abstract,
    Projection,
    Special,
    Lower,
    Frame,
    Literal,
    Never,
    Typevar,
    Infer,
    Error,
}

// What a variant's field holds. `Child`/`Children` are nested types: they
// are retargeted per member (the member itself, or a pool handle for an
// interned member); every other kind is copied as is.
enum FieldKind {
    Child,
    Children,
    Name,
    Id,
    LitValue,
    Freshness,
}

class Field {
    name: string,
    kind: FieldKind,
}

class Variant {
    name: string,
    axis: Axis,
    fields: Field[],

    function nests(self) -> bool {
        self.fields.some((f) -> {
            f.kind == FieldKind.Child || f.kind == FieldKind.Children
        })
    }
}

// `interned`: children are `int` handles into the hash-cons pool instead of
// the member itself (the `child: interned(..)` member).
class Member {
    name: string,
    // Function-name stem (`narrow_ty_to_runtime_ty`).
    snake: string,
    axes: Axis[],
    interned: bool,
}

// The bit each axis contributes to a pool entry's flags (`TypeFlags`).
class AxisFlag {
    axis: Axis,
    flag: string,
    bit: int,
}

class Family {
    variants: Variant[],
    members: Member[],
    flags: AxisFlag[],
}

function child(name: string) -> Field {
    Field { name: name, kind: FieldKind.Child }
}

function children(name: string) -> Field {
    Field { name: name, kind: FieldKind.Children }
}

function leaf(name: string, axis: Axis) -> Variant {
    Variant { name: name, axis: axis, fields: [] }
}

function f(name: string, kind: FieldKind) -> Field {
    Field { name: name, kind: kind }
}

function nest(name: string, axis: Axis, fields: Field[]) -> Variant {
    Variant { name: name, axis: axis, fields: fields }
}

// Full scale: the 32 variants of family.rs. Satellite positions
// (FunctionParamTy, Interface, associated-type pairs) are modelled as child
// lists of the same arity.
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

const FAMILY: Family = Family {
    variants: [
        leaf("Int", Axis.Concrete),
        leaf("Bigint", Axis.Concrete),
        leaf("Float", Axis.Concrete),
        leaf("String", Axis.Concrete),
        leaf("Bool", Axis.Concrete),
        leaf("Null", Axis.Concrete),
        leaf("Uint8Array", Axis.Concrete),
        nest("Media", Axis.Concrete, [f("kind", FieldKind.Name)]),
        nest(
            "Literal",
            Axis.Literal,
            [f("value", FieldKind.LitValue), f("freshness", FieldKind.Freshness)],
        ),
        nest("Class", Axis.Concrete, [f("name", FieldKind.Name), children("args")]),
        nest(
            "Interface",
            Axis.Abstract,
            [f("name", FieldKind.Name), children("args"), children("assoc")],
        ),
        nest("Enum", Axis.Concrete, [f("name", FieldKind.Name)]),
        nest("EnumVariant", Axis.Literal, [f("name", FieldKind.Name), f("variant", FieldKind.Name)]),
        nest("List", Axis.Concrete, [child("elem")]),
        nest("Map", Axis.Concrete, [child("key"), child("value")]),
        nest("Union", Axis.Abstract, [children("members")]),
        nest("Function", Axis.Concrete, [children("params"), child("ret"), child("throws_")]),
        nest("Future", Axis.Concrete, [child("value"), child("error")]),
        leaf("RustType", Axis.Concrete),
        leaf("Type", Axis.Concrete),
        leaf("Resource", Axis.Concrete),
        leaf("PromptAst", Axis.Concrete),
        nest("TypeAlias", Axis.Special, [f("name", FieldKind.Name)]),
        nest("TypeVar", Axis.Typevar, [f("name", FieldKind.Name)]),
        nest(
            "Projection",
            Axis.Projection,
            [child("base"), children("interface_args"), f("member", FieldKind.Name)],
        ),
        leaf("Unknown", Axis.Abstract),
        leaf("Never", Axis.Never),
        leaf("Error", Axis.Error),
        leaf("Infer", Axis.Lower),
        nest("InferVar", Axis.Infer, [f("id", FieldKind.Id)]),
        nest("TypeArgRef", Axis.Frame, [f("index", FieldKind.Id)]),
        nest("Tuple", Axis.Concrete, [children("items")]),
    ],
    members: [
        Member { name: "Ty", snake: "ty", axes: TY_AXES, interned: false },
        Member {
            name: "LoweringTy",
            snake: "lowering_ty",
            axes: TY_AXES.concat([Axis.Lower]),
            interned: false,
        },
        Member {
            name: "RuntimeTy",
            snake: "runtime_ty",
            axes: [
                Axis.Concrete,
                Axis.Abstract,
                Axis.Literal,
                Axis.Never,
                Axis.Typevar,
                Axis.Projection,
                Axis.Special,
            ],
            interned: false,
        },
        Member {
            name: "CodegenTy",
            snake: "codegen_ty",
            axes: [Axis.Concrete, Axis.Abstract, Axis.Literal, Axis.Never, Axis.Typevar, Axis.Special],
            interned: false,
        },
        Member {
            name: "RealizedTy",
            snake: "realized_ty",
            axes: [Axis.Concrete, Axis.Abstract, Axis.Literal, Axis.Never, Axis.Special],
            interned: false,
        },
        Member {
            name: "ConcreteTy",
            snake: "concrete_ty",
            axes: [Axis.Concrete, Axis.Never],
            interned: false,
        },
        Member {
            name: "TyTemplate",
            snake: "ty_template",
            axes: [
                Axis.Concrete,
                Axis.Abstract,
                Axis.Literal,
                Axis.Never,
                Axis.Projection,
                Axis.Special,
                Axis.Frame,
            ],
            interned: false,
        },
        Member {
            name: "InferTy",
            snake: "infer_ty",
            axes: TY_AXES.concat([Axis.Infer]),
            interned: true,
        },
    ],
    flags: [
        AxisFlag { axis: Axis.Infer, flag: "HAS_INFER", bit: 1 },
        AxisFlag { axis: Axis.Error, flag: "HAS_ERROR", bit: 2 },
        AxisFlag { axis: Axis.Typevar, flag: "HAS_TYPEVAR", bit: 4 },
        AxisFlag { axis: Axis.Projection, flag: "HAS_PROJECTION", bit: 8 },
    ],
};
