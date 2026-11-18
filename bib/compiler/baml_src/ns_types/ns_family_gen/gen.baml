// port: baml_type_macros @ d9be6853b (the `ty_family!` expansion)
//
// Writes the type family's BAML source from FAMILY (spec.baml). From the
// bib/compiler directory:
//
//   baml run types.family_gen.main -- --out baml_src/ns_types/family.baml
//
// The output is checked in and used like hand-written code; regenerate it
// after any change to spec.baml.

// How a nested position is converted while a value is rebuilt into another
// member: `fn(args..., child)`, or left as is when `identity`.
class Conv {
    fn: string,
    args: string,
    identity: bool,

    function call(self, e: string) -> string {
        if (self.identity) {
            e
        } else {
            `${self.fn}(${self.args}${e})`
        }
    }

    // `e` is a list; `depth` keeps nested lambda parameters distinct.
    function call_each(self, e: string, depth: int) -> string {
        if (self.identity) {
            e
        } else if (self.args) {
            `${e}.map((c${depth}) -> { ${self.call(`c${depth}`)} })`
        } else {
            `${e}.map(${self.fn})`
        }
    }
}

function via(fn: string) -> Conv {
    Conv { fn: fn, args: "", identity: false }
}

const IDENTITY: Conv = Conv { fn: "", args: "", identity: true };

function has(m: Member, v: Variant) -> bool {
    m.axes.includes(v.axis)
}

function variants_of(m: Member) -> Variant[] {
    FAMILY.variants.filter((v) -> {
        has(m, v)
    })
}

function member_named(name: string) -> Member {
    FAMILY.members.find((m) -> {
        m.name == name
    })
        ?? baml.sys.panic(`no family member \`${name}\``)
}

function satellite_named(name: string) -> Satellite {
    FAMILY.satellites.find((s) -> {
        s.name == name
    })
        ?? baml.sys.panic(`no satellite \`${name}\``)
}

// The members that are plain trees: everything but the interned member.
function plain_members() -> Member[] {
    FAMILY.members.filter((m) -> {
        !m.interned
    })
}

function interned_member() -> Member {
    FAMILY.members.find((m) -> {
        m.interned
    })
        ?? baml.sys.panic("the family has no interned member")
}

function deep(m: Member) -> bool {
    m.child == m.name
}

function child_of(m: Member) -> Member {
    member_named(m.child)
}

function subset(a: Member, b: Member) -> bool {
    a.axes.every((x) -> {
        b.axes.includes(x)
    })
}

// port: convert.rs::is_le. `a <= b` in the product order over the top-level
// variant set and the child member, at one head (Rust converts at one `N`).
function le(a: Member, b: Member) -> bool {
    a.head == b.head && subset(a, b) && subset(child_of(a), child_of(b))
}

// The distinct heads of the members that include `v`.
function heads_of(v: Variant) -> string[] {
    let heads: string[] = [];
    for (let m in FAMILY.members) {
        if (has(m, v) && !heads.includes(m.head)) {
            heads.push(m.head);
        }
    }
    heads
}

// A variant with no nested positions, and no head or one head across its
// members, is one class shared by every member, so it needs no conversion.
// Any other variant is a class per member.
function per_member(v: Variant) -> bool {
    v.nests() || (v.has_head() && heads_of(v).length() > 1)
}

function class_name(v: Variant, m: Member) -> string {
    if (per_member(v)) {
        `${m.name}${v.name}`
    } else {
        `Ty${v.name}`
    }
}

// Satellites are declared for deep and interned members; a shallow member
// reuses its child's (port: emit.rs, "satellites are generated only for deep
// members").
function satellite_owner(m: Member) -> Member {
    if (m.interned || deep(m)) {
        m
    } else {
        child_of(m)
    }
}

// port: emit.rs::satellite_name_for. `RuntimeTy` + `FunctionParamTy` is
// `RuntimeFunctionParamTy`; the master's satellites keep their bare names.
function satellite_class(s: Satellite, m: Member) -> string {
    let owner = satellite_owner(m).name;
    let prefix = if (owner.ends_with("Ty")) {
        owner.slice(0, owner.length() - 2)
    } else {
        owner
    };
    `${prefix}${s.name}`
}

function child_type(m: Member) -> string {
    if (m.interned) {
        "int"
    } else {
        m.child
    }
}

function field_type(f: Field, m: Member) -> string {
    match (f.kind) {
        FieldKind.Child => child_type(m),
        FieldKind.Children => `${child_type(m)}[]`,
        FieldKind.Head => m.head,
        FieldKind.Satellite => satellite_class(satellite_named(f.of), m),
        FieldKind.Satellites => `${satellite_class(satellite_named(f.of), m)}[]`,
        FieldKind.Opaque => f.of,
    }
}

function struct_decl(name: string, fields: Field[], m: Member) -> string {
    let body = fields
        .map((f) -> {
            `    ${f.name}: ${field_type(f, m)},\n`
        })
        .join("");
    `class ${name} {\n${body}}\n`
}

function shared_classes() -> string {
    FAMILY.variants
        .filter((v) -> {
            !per_member(v)
        })
        .map((v) -> {
            let m = FAMILY.members.find((m) -> {
                has(m, v)
            })
                ?? FAMILY.members[0];
            struct_decl(class_name(v, m), v.fields, m)
        })
        .join("\n")
}

function member_decls(m: Member) -> string {
    let vs = variants_of(m);
    let classes = vs
        .filter((v) -> {
            per_member(v)
        })
        .map((v) -> {
            struct_decl(class_name(v, m), v.fields, m)
        });
    let sats: string[] = if (satellite_owner(m).name == m.name) {
        FAMILY.satellites.map((s) -> {
            struct_decl(satellite_class(s, m), s.fields, m)
        })
    } else {
        []
    };
    let arms = vs
        .map((v) -> {
            class_name(v, m)
        })
        .join("\n    | ");
    let what = if (m.interned) {
        "interned: children are pool handles"
    } else if (deep(m)) {
        "deep"
    } else {
        `shallow over ${m.child}`
    };
    let title = `${m.name} (${what})`;
    `// -- ${title} ${"-".repeat(70 - title.length())}\n\n${classes.concat(sats).join("\n")}\ntype ${m.name} =\n    ${arms};\n`
}

// The fields of a value bound as `e`, rebuilt from member `from` into `to`.
function rebuild_fields(
    fields: Field[],
    from: Member,
    to: Member,
    conv: Conv,
    e: string,
    depth: int,
) -> string {
    fields
        .map((f) -> {
            let x = `${e}.${f.name}`;
            let value = match (f.kind) {
                FieldKind.Child => conv.call(x),
                FieldKind.Children => conv.call_each(x, depth),
                FieldKind.Satellite => {
                    rebuild_satellite(satellite_named(f.of), from, to, conv, x, depth)
                },
                FieldKind.Satellites => {
                    let s = satellite_named(f.of);
                    if (conv.identity && satellite_class(s, from) == satellite_class(s, to)) {
                        x
                    } else {
                        `${x}.map((s${depth}) -> { ${rebuild_satellite(s, from, to, conv, `s${depth}`, depth + 1)} })`
                    }
                },
                FieldKind.Head => x,
                FieldKind.Opaque => x,
            };
            `${f.name}: ${value}`
        })
        .join(", ")
}

function rebuild_satellite(
    s: Satellite,
    from: Member,
    to: Member,
    conv: Conv,
    e: string,
    depth: int,
) -> string {
    if (conv.identity && satellite_class(s, from) == satellite_class(s, to)) {
        e
    } else {
        `${satellite_class(s, to)} { ${rebuild_fields(s.fields, from, to, conv, e, depth)} }`
    }
}

// The arms of a match over `from` that rebuild each value as `to`: shared
// classes pass through (`wrap`ped), per-member classes are rebuilt with
// `conv` on their nested positions, and variants `to` lacks throw.
function convert_arms(from: Member, to: Member, conv: Conv, wrap: string) -> string[] {
    let wrapped = (e: string) -> string {
        if (wrap) {
            `${wrap}(${e})`
        } else {
            e
        }
    };
    let vs = variants_of(from);
    let kept = vs.filter((v) -> {
        has(to, v)
    });
    let shared = kept
        .filter((v) -> {
            !per_member(v)
        })
        .map((v) -> {
            class_name(v, from)
        });
    let pass: string[] = if (shared.length() == 0) {
        []
    } else {
        [`let x: ${shared.join(" | ")} => ${wrapped("x")},`]
    };
    let rebuilt = kept
        .filter((v) -> {
            per_member(v)
        })
        .map((v) -> {
            let built = `${class_name(v, to)} { ${rebuild_fields(v.fields, from, to, conv, "x", 0)} }`;
            `let x: ${class_name(v, from)} => ${wrapped(built)},`
        });
    let rejected = vs
        .filter((v) -> {
            !has(to, v)
        })
        .map((v) -> {
            `${class_name(v, from)} => throw NarrowError { variant: "${v.name}", into: "${to.name}" },`
        });
    pass.concat(rebuilt).concat(rejected)
}

function match_fn(signature: string, scrutinee: string, arms: string[]) -> string {
    let body = arms
        .map((a) -> {
            `        ${a}\n`
        })
        .join("");
    `${signature} {\n    match (${scrutinee}) {\n${body}    }\n}\n`
}

function convert_name(from: Member, to: Member) -> string {
    let verb = if (le(from, to)) {
        "widen"
    } else {
        "narrow"
    };
    `${verb}_${from.snake}_to_${to.snake}`
}

// port: convert.rs, one `From` (widening) or `TryFrom` (narrowing). Nested
// positions convert between the two members' children.
function convert_fn(from: Member, to: Member) -> string {
    let widening = le(from, to);
    let (let cf, let ct) = (child_of(from), child_of(to));
    let conv = if (cf.name == ct.name) {
        IDENTITY
    } else {
        via(convert_name(cf, ct))
    };
    let (let throws_, let doc) = if (widening) {
        ("never", `// Infallible: every ${from.name} is a ${to.name}.\n`)
    } else {
        ("NarrowError", `// Fails if any variant, at any depth, is outside ${to.name}.\n`)
    };
    let sig = `${doc}function ${convert_name(from, to)}(t: ${from.name}) -> ${to.name} throws ${throws_}`;
    match_fn(sig, "t", convert_arms(from, to, conv, ""))
}

function conversions() -> string {
    let ms = plain_members();
    ms
        .flat_map((a) -> {
            ms
                .filter((b) -> {
                    a.name != b.name && (le(a, b) || le(b, a))
                })
                .map((b) -> {
                    convert_fn(a, b)
                })
        })
        .join("\n")
}

// port: emit.rs::gen_child_walkers (`map_children`).
function map_children_fn(m: Member) -> string {
    let c = m.child;
    let sig = `// Rebuilds \`t\` with \`f\` applied to each direct child; leaves are returned as is.\nfunction map_children_${m.snake}(t: ${m.name}, f: (${c}) -> ${c}) -> ${m.name}`;
    match_fn(sig, "t", convert_arms(m, m, via("f"), ""))
}

// The expressions (each a list) of the children of a value bound as `e`.
function children_parts(fields: Field[], e: string, depth: int) -> string[] {
    fields.flat_map((f) -> {
        let x = `${e}.${f.name}`;
        match (f.kind) {
            FieldKind.Child => [`[${x}]`],
            FieldKind.Children => [x],
            FieldKind.Satellite => children_parts(satellite_named(f.of).fields, x, depth),
            FieldKind.Satellites => {
                let inner = children_parts(satellite_named(f.of).fields, `s${depth}`, depth + 1);
                [`${x}.flat_map((s${depth}) -> { ${concat_all(inner)} })`]
            },
            _ => [],
        }
    })
}

function concat_all(parts: string[]) -> string {
    if (parts.length() == 0) {
        return "[]";
    }
    parts.slice(1, parts.length()).reduce(
        (acc, p) -> {
            `${acc}.concat(${p})`
        },
        parts[0],
    )
}

// port: emit.rs::gen_child_walkers (`visit_children`), as a list.
function children_fn(m: Member) -> string {
    let vs = variants_of(m);
    let none = vs
        .filter((v) -> {
            !v.nests()
        })
        .map((v) -> {
            class_name(v, m)
        });
    let some = vs
        .filter((v) -> {
            v.nests()
        })
        .map((v) -> {
            `let x: ${class_name(v, m)} => ${concat_all(children_parts(v.fields, "x", 0))},`
        });
    let sig = `// The direct children of \`t\`, in field order.\nfunction children_${m.snake}(t: ${m.name}) -> ${child_type(m)}[]`;
    match_fn(sig, "t", [`${none.join(" | ")} => [],`].concat(some))
}

function intern_fn(m: Member, pool: Member) -> string {
    let name = `intern_${m.snake}`;
    let sig = `// Interns \`t\` bottom-up; returns its handle.\nfunction ${name}(pool: InferPool, t: ${m.name}) -> int`;
    let conv = Conv { fn: name, args: "pool, ", identity: false };
    match_fn(sig, "t", convert_arms(m, pool, conv, "pool.add"))
}

function resolve_fn(m: Member, pool: Member) -> string {
    let name = `resolve_${m.snake}`;
    let sig = `// Reads handle \`h\` back as a ${m.name}; fails on a variant outside it.\nfunction ${name}(pool: InferPool, h: int) -> ${m.name} throws NarrowError`;
    let conv = Conv { fn: name, args: "pool, ", identity: false };
    match_fn(sig, "pool.kinds[h]", convert_arms(pool, m, conv, ""))
}

// Interning and resolving between the deep members and the pool member, at
// the pool's head. (Rust writes these by hand in interned.rs; they are as
// mechanical as the rest.)
function interning() -> string {
    let pool = interned_member();
    let ms = plain_members().filter((m) -> {
        deep(m) && m.head == pool.head
    });
    let interns = ms
        .filter((m) -> {
            subset(m, pool)
        })
        .map((m) -> {
            intern_fn(m, pool)
        });
    let resolves = ms.map((m) -> {
        resolve_fn(m, pool)
    });
    [children_fn(pool)].concat(interns).concat(resolves).join("\n")
}

// `RuntimeFunctionParamTy` -> `runtime_function_param_ty`.
function snake_case(name: string) -> string {
    let out: string[] = [];
    let chars = name.split("");
    for (let i = 0; i < chars.length(); i += 1) {
        let c = chars[i];
        if (c != c.to_lower_case() && i > 0) {
            out.push("_");
        }
        out.push(c.to_lower_case());
    }
    out.join("")
}

// The comparison of an `Opaque` field's type (ord.baml or the built-in
// `cmp`).
function opaque_cmp(of: string) -> string {
    match (of) {
        "root.base.Literal" => "cmp_literal",
        "root.base.MediaKind" => "cmp_media_kind",
        "Freshness" => "cmp_freshness",
        "FunctionParamMode" => "cmp_function_param_mode",
        "ParamTy" => "cmp_param_ty",
        "string?" => "cmp_optional_string",
        _ => "",
    }
}

// `a.f` against `b.f` for field `f` of a value of member `m`.
function field_cmp(f: Field, m: Member, a: string, b: string) -> string {
    let x = `${a}.${f.name}`;
    let y = `${b}.${f.name}`;
    let child = `cmp_${member_named(m.child).snake}`;
    match (f.kind) {
        FieldKind.Child => `${child}(${x}, ${y})`,
        FieldKind.Children => `cmp_list(${x}, ${y}, ${child})`,
        FieldKind.Head => `cmp_${snake_case(m.head)}(${x}, ${y})`,
        FieldKind.Satellite => `cmp_${snake_case(satellite_class(satellite_named(f.of), m))}(${x}, ${y})`,
        FieldKind.Satellites => `cmp_list(${x}, ${y}, cmp_${snake_case(satellite_class(satellite_named(f.of), m))})`,
        FieldKind.Opaque => {
            let fn = opaque_cmp(f.of);
            if (fn) {
                `${fn}(${x}, ${y})`
            } else {
                `${x}.cmp(${y})`
            }
        },
    }
}

// The fields of `a` and `b` compared in order: the first that differs decides.
function fields_cmp(fields: Field[], m: Member, a: string, b: string, indent: string) -> string {
    let n = fields.length();
    let lines = fields.map((f) -> { field_cmp(f, m, a, b) });
    let early: string[] = [];
    for (let i = 0; i < n - 1; i += 1) {
        early.push(`${indent}let o${i} = ${lines[i]};\n${indent}if (o${i} != baml.ops.Ordering.Equal) {\n${indent}    return o${i};\n${indent}}\n`);
    }
    `${early.join("")}${indent}${lines[n - 1]}\n`
}

// port: the derived `Ord` of a member enum: variant declaration order, then
// fields in order.
function cmp_fn(m: Member) -> string {
    let vs = variants_of(m);
    let index_arms = vs.map((v) -> { `        ${class_name(v, m)} => ${FAMILY.variants.find_index((w) -> { w.name == v.name }) ?? 0},\n` }).join("");
    let field_arms = vs
        .filter((v) -> { v.fields.length() > 0 })
        .map((v) -> {
            let c = class_name(v, m);
            `        (let x: ${c}, let y: ${c}) => {\n${fields_cmp(v.fields, m, "x", "y", "            ")}        },\n`
        })
        .join("");
    `// The variant's position in declaration order.\nfunction variant_index_${m.snake}(t: ${m.name}) -> int throws never {\n    match (t) {\n${index_arms}    }\n}\n\n`
        + `// port: the derived Ord of ${m.name}.\nfunction cmp_${m.snake}(a: ${m.name}, b: ${m.name}) -> baml.ops.Ordering throws never {\n`
        + `    let by_variant = variant_index_${m.snake}(a).cmp(variant_index_${m.snake}(b));\n`
        + `    if (by_variant != baml.ops.Ordering.Equal) {\n        return by_variant;\n    }\n`
        + `    match ((a, b)) {\n${field_arms}        _ => baml.ops.Ordering.Equal,\n    }\n}\n`
}

// port: the derived Ord of a satellite struct.
function satellite_cmp_fn(s: Satellite, m: Member) -> string {
    let c = satellite_class(s, m);
    `// port: the derived Ord of ${c}.\nfunction cmp_${snake_case(c)}(a: ${c}, b: ${c}) -> baml.ops.Ordering throws never {\n${fields_cmp(s.fields, m, "a", "b", "    ")}}\n`
}

function ordering() -> string {
    plain_members()
        .flat_map((m) -> {
            let sats: string[] = if (deep(m)) { FAMILY.satellites.map((s) -> { satellite_cmp_fn(s, m) }) } else { [] };
            [cmp_fn(m)].concat(sats)
        })
        .join("\n")
}

function family_source() -> string {
    let header = "// GENERATED from ns_family_gen/spec.baml by `baml run types.family_gen.main`.\n// Do not edit by hand: change the spec and regenerate.\n";
    let section = (title: string) -> string {
        `// == ${title} ${"=".repeat(70 - title.length())}\n`
    };
    [
        header,
        section("Shared variants"),
        shared_classes(),
        FAMILY.members
            .map((m) -> {
                member_decls(m)
            })
            .join("\n"),
        section("Widening and narrowing"),
        conversions(),
        section("Child walkers"),
        plain_members()
            .flat_map((m) -> {
                [map_children_fn(m), children_fn(m)]
            })
            .join("\n"),
        section("Ordering"),
        ordering(),
        section("InferTy pool"),
        interning(),
    ]
        .join("\n")
}

function main(out: string) -> string {
    let source = family_source();
    baml.fs.write(out, source);
    let fmt = baml.sys.run("baml", args = ["fmt", out], capture_output = true);
    `wrote ${source.split("\n").length()} lines to ${out} (baml fmt exit ${fmt.exit_code})`
}
