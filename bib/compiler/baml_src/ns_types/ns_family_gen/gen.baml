// Writes the type family's BAML source from FAMILY (spec.baml).
//
//   baml run types.family_gen.main -- --out baml_src/ns_types/family.baml
//
// The output is checked in and used like hand-written code; regenerate it
// after any change to spec.baml.

// How a nested position is converted while a variant is rebuilt into another
// member: `fn(args..., child)`. `args` are leading arguments (the pool).
class Conv {
    fn: string,
    args: string,

    function call(self, e: string) -> string {
        `${self.fn}(${self.args}${e})`
    }

    function call_each(self, e: string) -> string {
        if (self.args) {
            `${e}.map((c) -> { ${self.call("c")} })`
        } else {
            `${e}.map(${self.fn})`
        }
    }
}

function has(m: Member, v: Variant) -> bool {
    m.axes.includes(v.axis)
}

function variants_of(m: Member) -> Variant[] {
    FAMILY.variants.filter((v) -> {
        has(m, v)
    })
}

function deep_members() -> Member[] {
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

function subset(a: Member, b: Member) -> bool {
    a.axes.every((x) -> {
        b.axes.includes(x)
    })
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
// Any other variant is a class per member: child fields are typed as that
// member, a head field as its head.
function per_member(v: Variant) -> bool {
    v.nests() || (v.has_head() && heads_of(v).length() > 1)
}

// Members are comparable (convertible) only at the same head, as in Rust,
// where the conversion matrix is between members at one `N`.
function comparable(a: Member, b: Member) -> bool {
    a.head == b.head && (subset(a, b) || subset(b, a))
}

function class_name(v: Variant, m: Member) -> string {
    if (per_member(v)) {
        `${m.name}${v.name}`
    } else {
        `Ty${v.name}`
    }
}

function field_type(f: Field, m: Member) -> string {
    let child_ty = if (m.interned) {
        "int"
    } else {
        m.name
    };
    match (f.kind) {
        FieldKind.Child => child_ty,
        FieldKind.Children => `${child_ty}[]`,
        FieldKind.Head => m.head,
        FieldKind.Name => "string",
        FieldKind.Media => "root.base.MediaKind",
        FieldKind.Id => "int",
        FieldKind.LitValue => "LitValue",
        FieldKind.Freshness => "Freshness",
    }
}

function class_decl(v: Variant, m: Member) -> string {
    let fields = v.fields
        .map((f) -> {
            `    ${f.name}: ${field_type(f, m)},\n`
        })
        .join("");
    `class ${class_name(v, m)} {\n${fields}}\n`
}

function leaf_classes() -> string {
    FAMILY.variants
        .filter((v) -> {
            !per_member(v)
        })
        .map((v) -> {
            class_decl(
                v,
                FAMILY.members.find((m) -> {
                    has(m, v)
                })
                    ?? FAMILY.members[0],
            )
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
            class_decl(v, m)
        })
        .join("\n");
    let arms = vs
        .map((v) -> {
            class_name(v, m)
        })
        .join("\n    | ");
    `// -- ${m.name} ${"-".repeat(70 - m.name.length())}\n\n${classes}\ntype ${m.name} =\n    ${arms};\n`
}

// `Target { f: conv(x.f), ... }` for variant `v` bound as `x`.
function rebuild(v: Variant, to: Member, conv: Conv) -> string {
    let fields = v.fields
        .map((f) -> {
            let e = `x.${f.name}`;
            let value = match (f.kind) {
                FieldKind.Child => conv.call(e),
                FieldKind.Children => conv.call_each(e),
                _ => e,
            };
            `${f.name}: ${value}`
        })
        .join(", ");
    `${class_name(v, to)} { ${fields} }`
}

function leaf_arm(leaves: Variant[], wrap: string) -> string[] {
    if (leaves.length() == 0) {
        return [];
    }
    let pattern = leaves
        .map((v) -> {
            `Ty${v.name}`
        })
        .join(" | ");
    let result = if (wrap) {
        `${wrap}(x)`
    } else {
        "x"
    };
    [`let x: ${pattern} => ${result},`]
}

// The arms of a match over `from` that rebuild each value as `to`: shared
// leaves pass through (`wrap`ped), nesting variants are rebuilt with `conv`,
// and variants `to` lacks throw a NarrowError.
function convert_arms(from: Member, to: Member, conv: Conv, wrap: string) -> string[] {
    let vs = variants_of(from);
    let kept = vs.filter((v) -> {
        has(to, v)
    });
    let leaves = leaf_arm(
        kept.filter((v) -> {
            !per_member(v)
        }),
        wrap,
    );
    let nested = kept
        .filter((v) -> {
            per_member(v)
        })
        .map((v) -> {
            let built = rebuild(v, to, conv);
            let result = if (wrap) {
                `${wrap}(${built})`
            } else {
                built
            };
            `let x: ${class_name(v, from)} => ${result},`
        });
    let rejected = vs
        .filter((v) -> {
            !has(to, v)
        })
        .map((v) -> {
            `${class_name(v, from)} => throw NarrowError { variant: "${v.name}", into: "${to.name}" },`
        });
    leaves.concat(nested).concat(rejected)
}

function match_fn(signature: string, scrutinee: string, arms: string[]) -> string {
    let body = arms
        .map((a) -> {
            `        ${a}\n`
        })
        .join("");
    `${signature} {\n    match (${scrutinee}) {\n${body}    }\n}\n`
}

function convert_fn(from: Member, to: Member) -> string {
    let widening = subset(from, to);
    let verb = if (widening) {
        "widen"
    } else {
        "narrow"
    };
    let name = `${verb}_${from.snake}_to_${to.snake}`;
    let throws_ = if (widening) {
        "never"
    } else {
        "NarrowError"
    };
    let doc = if (widening) {
        `// Infallible: every ${from.name} variant is a ${to.name} variant.\n`
    } else {
        `// Fails if any variant, at any depth, is outside ${to.name}.\n`
    };
    let sig = `${doc}function ${name}(t: ${from.name}) -> ${to.name} throws ${throws_}`;
    match_fn(sig, "t", convert_arms(from, to, Conv { fn: name, args: "" }, ""))
}

function conversions() -> string {
    let ms = deep_members();
    ms
        .flat_map((a) -> {
            ms
                .filter((b) -> {
                    a.name != b.name && comparable(a, b)
                })
                .map((b) -> {
                    convert_fn(a, b)
                })
        })
        .join("\n")
}

function map_children_fn(m: Member) -> string {
    let name = `map_children_${m.snake}`;
    let sig = `// Rebuilds \`t\` with \`f\` applied to each direct child; leaves are returned as is.\nfunction ${name}(t: ${m.name}, f: (${m.name}) -> ${m.name}) -> ${m.name}`;
    let arms = convert_arms(m, m, Conv { fn: "f", args: "" }, "");
    match_fn(sig, "t", arms)
}

function children_fn(m: Member) -> string {
    let vs = variants_of(m);
    let leaves = vs
        .filter((v) -> {
            !v.nests()
        })
        .map((v) -> {
            class_name(v, m)
        })
        .join(" | ");
    let nested = vs
        .filter((v) -> {
            v.nests()
        })
        .map((v) -> {
            let parts = v.fields.flat_map((f) -> {
                match (f.kind) {
                    FieldKind.Child => [`[x.${f.name}]`],
                    FieldKind.Children => [`x.${f.name}`],
                    _ => [],
                }
            });
            let first = parts[0];
            let all = parts.slice(1, parts.length()).reduce(
                (acc, p) -> {
                    `${acc}.concat(${p})`
                },
                first,
            );
            `let x: ${class_name(v, m)} => ${all},`
        });
    let sig = `// The direct children of \`t\`, in field order.\nfunction children_${m.snake}(t: ${m.name}) -> ${m.name}[]`;
    match_fn(sig, "t", [`${leaves} => [],`].concat(nested))
}

function intern_fn(m: Member, pool: Member) -> string {
    let name = `intern_${m.snake}`;
    let sig = `function ${name}(pool: InferPool, t: ${m.name}) -> int`;
    let arms = convert_arms(m, pool, Conv { fn: name, args: "pool, " }, "pool.add");
    match_fn(sig, "t", arms)
}

function resolve_fn(m: Member, pool: Member) -> string {
    let name = `resolve_${m.snake}`;
    let sig = `// Reads handle \`h\` back as a ${m.name}; fails on a variant outside it.\nfunction ${name}(pool: InferPool, h: int) -> ${m.name} throws NarrowError`;
    let arms = convert_arms(pool, m, Conv { fn: name, args: "pool, " }, "");
    match_fn(sig, "pool.kinds[h]", arms)
}

function own_flag(v: Variant) -> int {
    FAMILY.flags
        .find((f) -> {
            f.axis == v.axis
        })
        ?.bit
        ?? 0
}

// A pool entry's flags: its own axis bit or'ed with its children's flags.
function flags_fn(pool: Member) -> string {
    let arms = variants_of(pool).map((v) -> {
        let parts = v.fields.flat_map((f) -> {
            match (f.kind) {
                FieldKind.Child => [`pool.flags[x.${f.name}]`],
                FieldKind.Children => [`x.${f.name}.reduce((acc, c) -> { acc | pool.flags[c] }, 0)`],
                _ => [],
            }
        });
        let own = own_flag(v);
        if (parts.length() == 0) {
            return `${class_name(v, pool)} => ${own},`;
        }
        let all = if (own) {
            [own.to_string()].concat(parts)
        } else {
            parts
        };
        `let x: ${class_name(v, pool)} => ${all.join(" | ")},`
    });
    match_fn(`function infer_flags(pool: InferPool, k: ${pool.name}) -> int`, "k", arms)
}

function flag_consts() -> string {
    FAMILY.flags
        .map((f) -> {
            `const ${f.flag} = ${f.bit};\n`
        })
        .join("")
}

function interning() -> string {
    let pool = interned_member();
    let ms = deep_members().filter((m) -> {
        m.head == pool.head && subset(m, pool)
    });
    let interns = ms.map((m) -> {
        intern_fn(m, pool)
    });
    let resolves = deep_members()
        .filter((m) -> {
            m.head == pool.head
        })
        .map((m) -> {
            resolve_fn(m, pool)
        });
    [flag_consts(), flags_fn(pool)].concat(interns).concat(resolves).join("\n")
}

function family_source() -> string {
    let header = "// GENERATED from ns_family_gen/spec.baml by `baml run types.family_gen.main`.\n// Do not edit by hand: change the spec and regenerate.\n";
    let section = (title: string) -> string {
        `// == ${title} ${"=".repeat(70 - title.length())}\n`
    };
    [
        header,
        section("Shared leaf variants"),
        leaf_classes(),
        FAMILY.members
            .map((m) -> {
                member_decls(m)
            })
            .join("\n"),
        section("Widening and narrowing"),
        conversions(),
        section("Generic child walkers"),
        deep_members()
            .flat_map((m) -> {
                [map_children_fn(m), children_fn(m)]
            })
            .join("\n"),
        section("InferTy pool conversions"),
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
