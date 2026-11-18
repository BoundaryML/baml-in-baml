// port: baml_compiler2_mir/src/pretty.rs @ d9be6853b
//
// Human-readable MIR pretty printer, in the format of Rust's MIR dumps. This
// is the text every MIR oracle compares, byte for byte.
//
// Restructured (BAML forces it):
// - Rust writes into `&mut impl Write`; here every writer pushes onto a
//   `string[]` and the `display_*` entry points join it. `fmt::Result`
//   returns are `void`.
// - `Names::ty` / `template` / `interface` return Rust's display-headed
//   types (`baml_type::RuntimeTy<TypeName>`, heads packed by
//   `Viewpoint::wire_head`), which are then printed with `Display`. The
//   `root.types` family is `DeclName`-headed only, so those methods return
//   the printed text instead: each head is spelled as Rust's `HeadDisplay`
//   spells the wire head (`type_name_display_name(wire_head(decl))`, under
//   the canonical viewpoint always `<display label>.<ns>.<Name>`, e.g.
//   `user.fixtures.catch_throw.MayFail`), and the structure is printed by
//   `display_lowering_ty`, a port of baml_type's `impl Display for
//   LoweringTy` (which the family port leaves out: its `HeadDisplay` bound
//   excludes `DeclName`). A `TyTemplate` prints through
//   `template_display_ty` (template.rs `to_display_ty`), as Rust's
//   `impl Display for TyTemplate` does. The one `{:?}` (a `narrow_bind`
//   test) prints through `template_debug`, a port of the derived `Debug` of
//   `TyTemplate<TypeName>`.
// - `Constant::Float` prints with `rust_float_display` (Rust's `{}` of an
//   `f64`: no trailing `.0`, `inf`), `Constant::String` with
//   `root.base.rust_debug_string` (Rust's `{:?}`).
// - `type_tag_name` names `baml_type::typetag`'s constants by value: the
//   constants are not ported.

// port: baml_compiler2_mir/src/pretty.rs::Names @ d9be6853b
// MIR's heads are identities; a dump names them canonically
// (`Viewpoint::wire_head`). The one place a MIR type becomes text. Rust's
// tuple struct `Names(Viewpoint)`: the payload is `value`.
class Names {
    value: root.hir_ty.Viewpoint,

    // port: baml_compiler2_mir/src/pretty.rs::Names::of @ d9be6853b
    function of(db: root.hir.Db) -> Names throws never {
        Names { value: root.hir_ty.Viewpoint.canonical(db) }
    }

    // A head as Rust's `HeadDisplay` spells the wire head `wire_head` packs
    // it into (`TypeName::display_name`). The closure Rust's `map_heads`
    // takes.
    function head(self, decl: root.types.DeclName) -> string throws never {
        root.types.type_name_display_name(self.value.wire_head(decl))
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::ty @ d9be6853b
    // Restructured: returns the printed type (see the file header).
    function ty(self, ty: root.types.RuntimeTy) -> string throws never {
        display_lowering_ty(root.types.widen_runtime_ty_to_lowering_ty(ty), self)
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::template @ d9be6853b
    // Restructured: returns the printed template (see the file header).
    function template(self, template: root.types.TyTemplate) -> string throws never {
        display_lowering_ty(template_display_ty(template), self)
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::templates @ d9be6853b
    function templates(self, templates: root.types.TyTemplate[]) -> string throws never {
        templates
            .map((template) -> {
                self.template(template)
            })
            .join(", ")
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::interface @ d9be6853b
    // Restructured: returns the printed constraint, which Rust's
    // `impl Display for TyTemplateInterface` prints as the existential
    // template it denotes (`to_template`).
    function interface(
        self,
        interface_: root.types.TyTemplateInterfaceConstraint,
    ) -> string throws never {
        let existential: root.types.TyTemplate = root.types.TyTemplateInterface {
            name: interface_.name,
            args: interface_.generics,
            associated_types: interface_.associated_types,
        };
        self.template(existential)
    }
}

// port: baml_type/src/lib.rs::impl Display for LoweringTy @ d9be6853b
// Home: `root.types`. Rust's compact `Display` (not `render_with`): it
// differs from the canonical renderer on `!error` (`<error>`), on function
// parameters (types only, no names) and on type variables (the bare name).
// Heads are spelled by `names.head`, Rust's `HeadDisplay` of the wire head.
function display_lowering_ty(ty: root.types.LoweringTy, names: Names) -> string throws never {
    let show = (t: root.types.LoweringTy) -> string {
        display_lowering_ty(t, names)
    };
    match (ty) {
        root.types.TyInt => "int",
        root.types.TyFloat => "float",
        root.types.TyString => "string",
        root.types.TyBool => "bool",
        root.types.TyNull => "null",
        root.types.TyUint8Array => "uint8array",
        let m: root.types.TyMedia => root.base.media_kind_display(m.kind),
        let l: root.types.TyLiteral => root.base.literal_display(l.value),
        root.types.TyBigint => "bigint",
        let c: root.types.LoweringTyClass => {
            if (c.args.length() == 0) {
                names.head(c.name)
            } else {
                `${names.head(c.name)}<${c.args.map(show).join(", ")}>`
            }
        },
        let i: root.types.LoweringTyInterface => {
            let args = i.args.map(show).concat(
                i.associated_types.map((binding) -> {
                    `${binding.name} = ${show(binding.ty)}`
                }),
            );
            if (args.length() == 0) {
                names.head(i.name)
            } else {
                `${names.head(i.name)}<${args.join(", ")}>`
            }
        },
        let e: root.types.TyEnum => names.head(e.name),
        let v: root.types.TyEnumVariant => `${names.head(v.name)}.${v.variant}`,
        let a: root.types.TyTypeAlias => names.head(a.name),
        let l: root.types.LoweringTyList => `${display_postfix_base(l.elem, names)}[]`,
        let m: root.types.LoweringTyMap => `map<${show(m.key)}, ${show(m.value)}>`,
        let t: root.types.LoweringTyTuple => root.types.render_tuple(t.items.map(show)),
        // `?` is sugar that exists only in source/lowering; after that a
        // nullable type is a plain union and renders as `T | null`. Function
        // members are parenthesized so a nullable callback reads as
        // `((..) -> ..) | null`, not a function with `throws .. | null`.
        let u: root.types.LoweringTyUnion => {
            u.members
                .map((member) -> {
                    let rendered = show(member);
                    if (member is root.types.LoweringTyFunction) {
                        `(${rendered})`
                    } else {
                        rendered
                    }
                })
                .join(" | ")
        },
        let f: root.types.LoweringTyFunction => {
            let params = f.params.map((param) -> {
                show(param.ty)
            });
            let ret = if (f.ret is root.types.LoweringTyFunction) {
                `(${show(f.ret)})`
            } else {
                show(f.ret)
            };
            `(${params.join(", ")}) -> ${ret} throws ${show(f.throws_)}`
        },
        root.types.TyUnknown => "unknown",
        // The writable spelling: lowercase `future<..>` resolves nowhere.
        let f: root.types.LoweringTyFuture => {
            `baml.future.Future<${show(f.value)}, ${show(f.error)}>`
        },
        let v: root.types.TyTypeVar => v.param.name,
        let p: root.types.LoweringTyAssociatedTypeProjection => {
            let existential: root.types.LoweringTy = root.types.LoweringTyInterface {
                name: p.interface_.name,
                args: p.interface_.generics,
                associated_types: p.interface_.associated_types,
            };
            `(${show(p.base)} as ${show(existential)}).${p.member}`
        },
        root.types.TyNever => "never",
        root.types.TyError => "<error>",
        root.types.TyInfer => "_",
        // Opaque leaf types: render identically to `render_with`.
        root.types.TyRustType => "$rust_type",
        root.types.TyType => "reflect.Type",
        root.types.TyResource => "ai.Resource",
        root.types.TyPromptAst => "ai.Prompt",
    }
}

// port: baml_type/src/lib.rs::LoweringTy::fmt_as_postfix_base @ d9be6853b
// Home: `root.types`. Parenthesized in postfix (`[]`) position when needed.
function display_postfix_base(ty: root.types.LoweringTy, names: Names) -> string throws never {
    let inner = display_lowering_ty(ty, names);
    if (root.types.needs_postfix_parens(ty)) {
        `(${inner})`
    } else {
        inner
    }
}

// port: baml_type/src/template.rs::TyTemplate::to_display_ty @ d9be6853b
// Home: `root.types`. The template as the type it prints as: a frame
// reference shows as `#n` (a type variable named `#n`). Restructured: the
// result is the `LoweringTy` Rust's `Ty` `Display` upcasts to, so a realized
// leaf (a class shared by both members) is returned as it is.
function template_display_ty(
    template: root.types.TyTemplate,
) -> root.types.LoweringTy throws never {
    match (template) {
        let r: root.types.TyTypeArgRef => {
            root.types.TyTypeVar {
                param: root.types.ParamTy { index: r.index, name: `#${r.index}` },
            }
        },
        let l: root.types.TyTemplateList => {
            root.types.LoweringTyList { elem: template_display_ty(l.elem) }
        },
        let m: root.types.TyTemplateMap => {
            root.types.LoweringTyMap {
                key: template_display_ty(m.key),
                value: template_display_ty(m.value),
            }
        },
        let u: root.types.TyTemplateUnion => {
            root.types.LoweringTyUnion { members: u.members.map(template_display_ty) }
        },
        let t: root.types.TyTemplateTuple => {
            root.types.LoweringTyTuple { items: t.items.map(template_display_ty) }
        },
        let c: root.types.TyTemplateClass => {
            root.types.LoweringTyClass { name: c.name, args: c.args.map(template_display_ty) }
        },
        let i: root.types.TyTemplateInterface => {
            root.types.LoweringTyInterface {
                name: i.name,
                args: i.args.map(template_display_ty),
                associated_types: i.associated_types.map((binding) -> {
                    root.types.LoweringAssociatedType {
                        name: binding.name,
                        ty: template_display_ty(binding.ty),
                    }
                }),
            }
        },
        let f: root.types.TyTemplateFunction => {
            root.types.LoweringTyFunction {
                params: f.params.map((param) -> {
                    root.types.LoweringFunctionParamTy {
                        name: param.name,
                        ty: template_display_ty(param.ty),
                        mode: param.mode,
                    }
                }),
                ret: template_display_ty(f.ret),
                throws_: template_display_ty(f.throws_),
            }
        },
        let f: root.types.TyTemplateFuture => {
            root.types.LoweringTyFuture {
                value: template_display_ty(f.value),
                error: template_display_ty(f.error),
            }
        },
        let p: root.types.TyTemplateAssociatedTypeProjection => {
            root.types.LoweringTyAssociatedTypeProjection {
                base: template_display_ty(p.base),
                interface_: root.types.LoweringInterfaceConstraint {
                    name: p.interface_.name,
                    generics: p.interface_.generics.map(template_display_ty),
                    associated_types: p.interface_.associated_types.map((binding) -> {
                        root.types.LoweringAssociatedType {
                            name: binding.name,
                            ty: template_display_ty(binding.ty),
                        }
                    }),
                },
                member: p.member,
            }
        },
        // A realized leaf is a variant both members share.
        let t: root.types.TyInt => t,
        let t: root.types.TyBigint => t,
        let t: root.types.TyFloat => t,
        let t: root.types.TyString => t,
        let t: root.types.TyBool => t,
        let t: root.types.TyNull => t,
        let t: root.types.TyUint8Array => t,
        let t: root.types.TyMedia => t,
        let t: root.types.TyLiteral => t,
        let t: root.types.TyEnum => t,
        let t: root.types.TyEnumVariant => t,
        let t: root.types.TyRustType => t,
        let t: root.types.TyType => t,
        let t: root.types.TyResource => t,
        let t: root.types.TyPromptAst => t,
        let t: root.types.TyTypeAlias => t,
        let t: root.types.TyUnknown => t,
        let t: root.types.TyNever => t,
    }
}

// port: baml_type/src/family.rs::TyTemplate (derived Debug) @ d9be6853b
// Home: `root.types`. Rust's derived `{:?}` of a `TyTemplate<TypeName>`,
// heads packed by `wire_head` as `Names` packs them: unit variants by name,
// tuple variants as `Name(a, b)`, struct variants and satellites as
// `Name { field: value, .. }`, slices as `[a, b]`, names (`SmolStr`) and
// strings quoted.
function template_debug(template: root.types.TyTemplate, names: Names) -> string throws never {
    let show = (t: root.types.TyTemplate) -> string {
        template_debug(t, names)
    };
    let list = (items: root.types.TyTemplate[]) -> string {
        `[${items.map(show).join(", ")}]`
    };
    let head = (decl: root.types.DeclName) -> string {
        type_name_debug(names.value.wire_head(decl))
    };
    let bindings = (items: root.types.TyTemplateAssociatedType[]) -> string {
        let parts = items.map((binding) -> {
            `(${root.base.rust_debug_string(binding.name)}, ${show(binding.ty)})`
        });
        `[${parts.join(", ")}]`
    };
    match (template) {
        root.types.TyInt => "Int",
        root.types.TyBigint => "Bigint",
        root.types.TyFloat => "Float",
        root.types.TyString => "String",
        root.types.TyBool => "Bool",
        root.types.TyNull => "Null",
        root.types.TyUint8Array => "Uint8Array",
        let m: root.types.TyMedia => `Media(${m.kind})`,
        let l: root.types.TyLiteral => `Literal(${literal_debug(l.value)}, ${l.freshness})`,
        let c: root.types.TyTemplateClass => `Class(${head(c.name)}, ${list(c.args)})`,
        let i: root.types.TyTemplateInterface => {
            `Interface(${head(i.name)}, ${list(i.args)}, ${bindings(i.associated_types)})`
        },
        let e: root.types.TyEnum => `Enum(${head(e.name)})`,
        let v: root.types.TyEnumVariant => {
            `EnumVariant(${head(v.name)}, ${root.base.rust_debug_string(v.variant)})`
        },
        let l: root.types.TyTemplateList => `List(${show(l.elem)})`,
        let m: root.types.TyTemplateMap => `Map { key: ${show(m.key)}, value: ${show(m.value)} }`,
        let u: root.types.TyTemplateUnion => `Union(${list(u.members)})`,
        let f: root.types.TyTemplateFunction => {
            let params = f.params.map((param) -> {
                let name = param.name;
                let name_debug = if (name == null) {
                    "None"
                } else {
                    `Some(${root.base.rust_debug_string(name)})`
                };
                `TyTemplateFunctionParamTy { name: ${name_debug}, ty: ${show(param.ty)}, mode: ${param.mode} }`
            });
            `Function { params: [${params.join(", ")}], ret: ${show(f.ret)}, throws: ${show(f.throws_)} }`
        },
        let f: root.types.TyTemplateFuture => `Future(${show(f.value)}, ${show(f.error)})`,
        root.types.TyRustType => "RustType",
        root.types.TyType => "Type",
        root.types.TyResource => "Resource",
        root.types.TyPromptAst => "PromptAst",
        let a: root.types.TyTypeAlias => `TypeAlias(${head(a.name)})`,
        let p: root.types.TyTemplateAssociatedTypeProjection => {
            let iface = p.interface_;
            let interface_debug = `TyTemplateInterface { name: ${head(iface.name)}, generics: ${list(iface.generics)}, associated_types: ${bindings(iface.associated_types)} }`;
            `AssociatedTypeProjection { base: ${show(p.base)}, interface: ${interface_debug}, member: ${root.base.rust_debug_string(p.member)} }`
        },
        root.types.TyUnknown => "Unknown",
        root.types.TyNever => "Never",
        let r: root.types.TyTypeArgRef => `TypeArgRef(${r.index})`,
        let t: root.types.TyTemplateTuple => `Tuple(${list(t.items)})`,
    }
}

// port: baml_type/src/names.rs::QualifiedTypeName (derived Debug) @ d9be6853b
// Home: `root.types`. Rust's derived `{:?}` of a `TypeName`.
function type_name_debug(name: root.types.TypeName) -> string throws never {
    let pkg = match (name.pkg) {
        root.types.PackageLocal => "Local",
        let d: root.types.PackageDep => `Dep(${root.base.rust_debug_string(d.value)})`,
    };
    let namespace = name.namespace.map((segment) -> {
        root.base.rust_debug_string(segment)
    });
    `QualifiedTypeName { pkg: ${pkg}, namespace: [${namespace.join(", ")}], name: ${root.base.rust_debug_string(name.name)} }`
}

// port: baml_base/src/core_types.rs::Literal (derived Debug) @ d9be6853b
// Home: `root.base`. Rust's derived `{:?}` of a `Literal`.
function literal_debug(literal: root.base.Literal) -> string throws never {
    match (literal) {
        let l: root.base.LiteralInt => `Int(${l.value})`,
        let l: root.base.LiteralBigint => `Bigint(${l.value})`,
        let l: root.base.LiteralFloat => `Float(${root.base.rust_debug_string(l.value)})`,
        let l: root.base.LiteralString => `String(${root.base.rust_debug_string(l.value)})`,
        let l: root.base.LiteralBool => `Bool(${l.value})`,
    }
}

// Rust's `{}` of an `f64`: integral values print without a fractional part
// (`1`, not `1.0`), infinities as `inf` / `-inf`. BAML's `to_string` agrees
// otherwise (shortest round-trip digits, no exponent).
function rust_float_display(value: float) -> string throws never {
    let text = value.to_string();
    match (text) {
        "Infinity" => "inf",
        "-Infinity" => "-inf",
        _ => {
            if (text.ends_with(".0")) {
                text.slice(0, text.length() - 2)
            } else {
                text
            }
        },
    }
}

// port: baml_compiler2_mir/src/pretty.rs::display_function @ d9be6853b
// Pretty print a MIR function.
function display_function(db: root.hir.Db, func: MirFunction) -> string throws never {
    let output: string[] = [];
    write_function(output, db, func);
    output.join("")
}

// port: baml_compiler2_mir/src/pretty.rs::write_function @ d9be6853b
// Write a MIR function to a formatter.
function write_function(f: string[], db: root.hir.Db, func: MirFunction) -> void throws never {
    match (func.kind) {
        let builtin: MirFunctionKindBuiltin => {
            let kind_str = match (builtin.value) {
                root.ast.BuiltinKind.Io => "io",
                root.ast.BuiltinKind.Vm => "vm",
                root.ast.BuiltinKind.Intrinsic => "intrinsic",
                root.ast.BuiltinKind.AwaitAny => "await_any",
                root.ast.BuiltinKind.Spawn => "spawn",
            };
            f.push(`fn ${mir_function_id_display_name(db, func.identity)} = builtin(${kind_str})\n`);
        },
        let bytecode: MirFunctionKindBytecode => {
            write_bytecode_function(f, db, func, bytecode.value)
        },
    }
}

// port: baml_compiler2_mir/src/pretty.rs::write_bytecode_function @ d9be6853b
// Write the bytecode body of a MIR function.
function write_bytecode_function(
    f: string[],
    db: root.hir.Db,
    func: MirFunction,
    body: MirFunctionBody,
) -> void throws never {
    // Function header
    f.push(`fn ${mir_function_id_display_name(db, func.identity)}(`);

    // Parameters (_1 through _arity)
    for (let i = 1; i <= func.arity; i += 1) {
        if (i > 1) {
            f.push(", ");
        }
        // Guard against missing locals in error recovery cases
        if (i < body.locals.length()) {
            write_local_decl_inline(f, db, i, body.locals[i]);
        } else {
            f.push(`_${i}: <missing>`);
        }
    }

    // Return type from _0
    f.push(")");
    if (body.locals.length() > 0) {
        f.push(` -> ${Names.of(db).ty(body.locals[0].ty)}`);
    }
    f.push(" {\n");
    write_body(f, db, body, func.arity);
    f.push("}\n");

    // Recursively display child lambda functions, labeled by index.
    for (let idx = 0; idx < func.lambdas.length(); idx += 1) {
        f.push("\n");
        f.push(`// lambda[${idx}]\n`);
        write_function(f, db, func.lambdas[idx]);
    }
}

// port: baml_compiler2_mir/src/pretty.rs::display_body @ d9be6853b
// Pretty print a function body on its own: its locals and blocks, without
// the signature header.
function display_body(db: root.hir.Db, body: MirFunctionBody, arity: int) -> string throws never {
    let output: string[] = [];
    write_body(output, db, body, arity);
    output.join("")
}

// port: baml_compiler2_mir/src/pretty.rs::write_body @ d9be6853b
// Write a body's locals and blocks.
function write_body(
    f: string[],
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
) -> void throws never {
    f.push("    // Locals:\n");
    for (let i = 0; i < body.locals.length(); i += 1) {
        let local = body.locals[i];
        f.push(`    let _${i}: ${Names.of(db).ty(local.ty)}`);
        let name = local.name;
        if (name != null) {
            f.push(` // ${name}`);
        }
        if (i == 0) {
            f.push(" // return");
        } else if (i <= arity) {
            f.push(" // param");
        }
        if (local.is_captured) {
            f.push(" [captured]");
        }
        f.push("\n");
    }
    f.push("\n");

    for (let i = 0; i < body.blocks.length(); i += 1) {
        write_block(f, db, body.blocks[i]);
        if (i + 1 < body.blocks.length()) {
            f.push("\n");
        }
    }
}

// port: baml_compiler2_mir/src/pretty.rs::write_local_decl_inline @ d9be6853b
function write_local_decl_inline(
    f: string[],
    db: root.hir.Db,
    id: int,
    decl: LocalDecl,
) -> void throws never {
    let ty = Names.of(db).ty(decl.ty);
    let name = decl.name;
    if (name != null) {
        f.push(`${name}: ${ty}`);
    } else {
        f.push(`${local_to_string(id)}: ${ty}`);
    }
}

// port: baml_compiler2_mir/src/pretty.rs::write_block @ d9be6853b
function write_block(f: string[], db: root.hir.Db, block: BasicBlock) -> void throws never {
    f.push(`    ${block_id_to_string(block.id)}`);
    let landing = block.landing;
    if (landing != null) {
        f.push(
            ` [landing ${local_to_string(landing.error_local)}, ${local_to_string(landing.context_local)}]`,
        );
    }
    let unwind = block.unwind;
    if (unwind != null) {
        f.push(` [unwind ${block_id_to_string(unwind)}]`);
    }
    let handling = block.handling;
    if (handling != null) {
        f.push(` [handling ${block_id_to_string(handling)}]`);
    }
    if (block.shielded) {
        f.push(" [shielded]");
    }
    f.push(": {\n");

    for (let stmt in block.statements) {
        f.push("        ");
        write_statement(f, db, stmt);
        f.push("\n");
    }

    let term = block.terminator;
    if (term != null) {
        f.push("        ");
        write_terminator(f, db, term);
        f.push("\n");
    } else {
        f.push("        // unterminated\n");
    }

    f.push("    }\n");
}

// The operands `args` written `, `-separated.
// Restructured: Rust repeats this loop inline at each site.
function write_operand_list(f: string[], db: root.hir.Db, args: Operand[]) -> void throws never {
    for (let i = 0; i < args.length(); i += 1) {
        if (i > 0) {
            f.push(", ");
        }
        write_operand(f, db, args[i]);
    }
}

// port: baml_compiler2_mir/src/pretty.rs::write_statement @ d9be6853b
function write_statement(f: string[], db: root.hir.Db, stmt: Statement) -> void throws never {
    match (stmt.kind) {
        let s: StatementKindAssign => {
            f.push(`${place_to_string(s.destination)} = `);
            write_rvalue(f, db, s.value);
            f.push(";");
        },
        let s: StatementKindVirtualFieldStore => {
            write_operand(f, db, s.receiver);
            f.push(`.${s.field}#${s.field_index} as ${Names.of(db).interface(s.iface)} = `);
            write_operand(f, db, s.value);
            f.push(";");
        },
        let s: StatementKindDrop => {
            f.push(`drop(${place_to_string(s.value)});`);
        },
        let s: StatementKindFreshCell => {
            if (s.carry_value) {
                f.push(`fresh_cell(${local_to_string(s.local)}, carry);`);
            } else {
                f.push(`fresh_cell(${local_to_string(s.local)});`);
            }
        },
        let s: StatementKindIntrinsic => write_intrinsic_statement(f, db, s),
        StatementKindNop => {
            f.push("nop;");
        },
    }
}

// The `StatementKind::Intrinsic` arm of `write_statement`.
// Restructured: Rust's early `return write!(..)` arms become this helper's
// own early returns.
function write_intrinsic_statement(
    f: string[],
    db: root.hir.Db,
    stmt: StatementKindIntrinsic,
) -> void throws never {
    let op_str = match (stmt.op) {
        IntrinsicOpApplyTraceHook => "apply_trace_hook",
        let op: IntrinsicOpBuiltinTraceHook => {
            f.push(`builtin_trace_hook(${op.value});`);
            return;
        },
        let op: IntrinsicOpLog => {
            match (op.value) {
                LogLevel.Info => "log_info",
                LogLevel.Debug => "log_debug",
                LogLevel.Warn => "log_warn",
                LogLevel.Error => "log_error",
            }
        },
        let op: IntrinsicOpBindType => {
            f.push(`bind_type(${op.value}`);
            for (let arg in stmt.args) {
                f.push(", ");
                write_operand(f, db, arg);
            }
            f.push(");");
            return;
        },
    };
    f.push(`intrinsic ${op_str}(`);
    write_operand_list(f, db, stmt.args);
    f.push(");");
}

// port: baml_compiler2_mir/src/pretty.rs::write_terminator @ d9be6853b
// Restructured: the `Switch`, `Call` and `VirtualCall` arms are
// `write_switch_terminator` and `write_call_args`.
function write_terminator(f: string[], db: root.hir.Db, term: Terminator) -> void throws never {
    match (term) {
        let t: TerminatorGoto => {
            f.push(`goto -> ${block_id_to_string(t.target)};`);
        },
        let t: TerminatorBranch => {
            f.push("branch ");
            write_operand(f, db, t.condition);
            f.push(
                ` -> [${block_id_to_string(t.then_block)}, ${block_id_to_string(t.else_block)}];`,
            );
        },
        let t: TerminatorNarrowBind => {
            f.push(`${local_to_string(t.destination)} = narrow_bind `);
            write_operand(f, db, t.source);
            let names = Names.of(db);
            let test_debug = template_debug(type_test_template(db, t.test_), names);
            f.push(
                ` as ${test_debug} -> [${block_id_to_string(t.then_block)}, ${block_id_to_string(t.else_block)}];`,
            );
        },
        let t: TerminatorSwitch => write_switch_terminator(f, db, t),
        TerminatorReturn => {
            f.push("return;");
        },
        let t: TerminatorCall => {
            f.push(`${place_to_string(t.destination)} = call `);
            write_operand(f, db, t.callee);
            write_call_args(f, db, t.args, t.ntypeargs);
            f.push(`) -> [${block_id_to_string(t.target)}`);
            write_unwind_suffix(f, t.unwind);
        },
        let t: TerminatorVirtualCall => {
            f.push(
                `${place_to_string(t.destination)} = virtual_call ${t.method} as ${Names.of(db).interface(t.iface)}`,
            );
            write_call_args(f, db, t.args, t.ntypeargs);
            f.push(")");
            // The receiver position is the norm; only a dispatch elsewhere
            // is worth a word.
            if (t.self_arg != 0) {
                f.push(` self_arg=${t.self_arg}`);
            }
            f.push(` -> [${block_id_to_string(t.target)}`);
            write_unwind_suffix(f, t.unwind);
        },
        TerminatorUnreachable => {
            f.push("unreachable;");
        },
        let t: TerminatorSysOp => {
            f.push(`${place_to_string(t.destination)} = sys_op `);
            write_operand(f, db, t.callee);
            f.push("(");
            write_operand_list(f, db, t.args);
            f.push(`) -> ${block_id_to_string(t.target)}`);
            let unwind = t.unwind;
            if (unwind != null) {
                f.push(` unwind ${block_id_to_string(unwind)}`);
            }
            f.push(";");
        },
        let t: TerminatorSpawn => {
            f.push(`${place_to_string(t.future)} = spawn `);
            write_operand(f, db, t.plan);
            f.push(` -> ${block_id_to_string(t.resume)};`);
        },
        let t: TerminatorAwait => {
            f.push(
                `${place_to_string(t.destination)} = await ${place_to_string(t.future)} -> [${block_id_to_string(t.target)}`,
            );
            write_unwind_suffix(f, t.unwind);
        },
        let t: TerminatorAwaitAny => {
            f.push(`${place_to_string(t.destination)} = await_any `);
            write_operand(f, db, t.futures);
            f.push(` -> [${block_id_to_string(t.target)}`);
            write_unwind_suffix(f, t.unwind);
        },
        let t: TerminatorThrow => {
            f.push("throw ");
            write_operand(f, db, t.value);
            f.push(";");
        },
        let t: TerminatorRethrow => {
            f.push("rethrow ");
            write_operand(f, db, t.value);
            f.push(" with ");
            write_operand(f, db, t.context);
            f.push(";");
        },
        let t: TerminatorShortCircuit => {
            let op = match (t.kind) {
                ShortCircuitKind.And => "&&",
                ShortCircuitKind.Or => "||",
                ShortCircuitKind.Coalesce => "??",
            };
            f.push(`${place_to_string(t.destination)} = short_circuit(${op}) `);
            write_operand(f, db, t.operand);
            f.push(
                ` -> [eval: ${block_id_to_string(t.eval_rhs)}, join: ${block_id_to_string(t.join)}];`,
            );
        },
    }
}

// The `Terminator::Switch` arm of `write_terminator`.
function write_switch_terminator(
    f: string[],
    db: root.hir.Db,
    t: TerminatorSwitch,
) -> void throws never {
    f.push("switch ");
    write_operand(f, db, t.discriminant);
    f.push(" [");
    for (let i = 0; i < t.arms.length(); i += 1) {
        if (i > 0) {
            f.push(", ");
        }
        let key = t.arms[i].0;
        let target = block_id_to_string(t.arms[i].1);
        // Rust's name lookup is a `HashMap` built from `arm_names`: a key
        // named twice keeps its last name.
        let name: string? = null;
        for (let entry in t.arm_names) {
            if (entry.0 == key) {
                name = entry.1;
            }
        }
        if (name != null) {
            f.push(`${name}: ${target}`);
        } else {
            match (key) {
                let k: SwitchKeyInt => {
                    f.push(`${k.value}: ${target}`);
                },
                let k: SwitchKeyClass => {
                    f.push(`${class_display_name(db, k.value)}: ${target}`);
                },
            }
        }
    }
    if (t.exhaustive) {
        f.push(`, otherwise: ${block_id_to_string(t.otherwise)}] (exhaustive);`);
    } else {
        f.push(`, otherwise: ${block_id_to_string(t.otherwise)}];`);
    }
}

// The `<type args>(value args` of a call: the first `ntypeargs` operands in
// angle brackets (when there are any), then the rest after an open paren.
// Restructured: Rust repeats this in the `Call` and `VirtualCall` arms.
function write_call_args(
    f: string[],
    db: root.hir.Db,
    args: Operand[],
    ntypeargs: int,
) -> void throws never {
    if (ntypeargs > 0) {
        f.push("<");
        write_operand_list(f, db, args.slice(0, ntypeargs));
        f.push(">");
    }
    f.push("(");
    if (ntypeargs < args.length()) {
        write_operand_list(f, db, args.slice(ntypeargs, args.length()));
    }
}

// The `, unwind: bbN];` (or `];`) closing a call-like terminator.
// Restructured: Rust repeats this in each call-like arm.
function write_unwind_suffix(f: string[], unwind: int?) -> void throws never {
    if (unwind != null) {
        f.push(`, unwind: ${block_id_to_string(unwind)}`);
    }
    f.push("];");
}

// port: baml_compiler2_mir/src/pretty.rs::write_rvalue @ d9be6853b
function write_rvalue(f: string[], db: root.hir.Db, rvalue: Rvalue) -> void throws never {
    match (rvalue) {
        let r: RvalueTraceHookSettings => {
            f.push(`trace_hook_settings(${r.with_settings})`);
        },
        let r: RvalueUse => write_operand(f, db, r.value),
        let r: RvalueVirtualFieldAccess => {
            write_operand(f, db, r.receiver);
            f.push(`.${r.field}#${r.field_index} as ${Names.of(db).interface(r.iface)}`);
        },
        let r: RvalueBinaryOp => {
            write_operand(f, db, r.left);
            f.push(` ${bin_op_to_string(r.op)} `);
            write_operand(f, db, r.right);
        },
        let r: RvalueUnaryOp => {
            f.push(unary_op_to_string(r.op));
            write_operand(f, db, r.operand);
        },
        let r: RvalueConcatStrings => {
            f.push("concat(");
            write_operand_list(f, db, r.value);
            f.push(")");
        },
        let r: RvalueArray => {
            f.push("[");
            write_operand_list(f, db, r.elements);
            // Show the emitted element-type template so MIR snapshots can
            // catch a wrong array element type.
            f.push(`]: ${Names.of(db).template(r.element_ty)}[]`);
        },
        let r: RvalueUint8Array => {
            f.push(`b"<${r.value.length()} bytes>"`);
        },
        let r: RvalueMap => {
            f.push("{ ");
            for (let i = 0; i < r.entries.length(); i += 1) {
                if (i > 0) {
                    f.push(", ");
                }
                write_operand(f, db, r.entries[i].0);
                f.push(": ");
                write_operand(f, db, r.entries[i].1);
            }
            f.push(
                ` }: map<${Names.of(db).template(r.key_ty)}, ${Names.of(db).template(r.value_ty)}>`,
            );
        },
        let r: RvalueAggregate => {
            match (r.kind) {
                AggregateKindArray => {
                    f.push("array");
                },
                let k: AggregateKindClass => {
                    f.push(class_display_name(db, k.class_));
                    if (k.type_arg_templates.length() > 0) {
                        f.push(`<${Names.of(db).templates(k.type_arg_templates)}>`);
                    }
                },
                let k: AggregateKindTuple => {
                    f.push(`tuple(${Names.of(db).templates(k.element_templates)})`);
                },
            }
            f.push(" { ");
            write_operand_list(f, db, r.fields);
            f.push(" }");
        },
        let r: RvalueDiscriminant => {
            f.push(`discriminant(${place_to_string(r.value)})`);
        },
        let r: RvalueTypeTag => {
            f.push(`type_tag(${place_to_string(r.value)})`);
        },
        let r: RvalueLen => {
            f.push(`len(${place_to_string(r.value)})`);
        },
        let r: RvalueIsType => {
            f.push("is_type(");
            write_operand(f, db, r.operand);
            f.push(`, ${Names.of(db).template(type_test_template(db, r.test_))})`);
        },
        let r: RvalueSatisfiesBound => {
            f.push("satisfies_bound(");
            write_operand(f, db, r.ty);
            f.push(`, ${Names.of(db).interface(r.bound)})`);
        },
        let r: RvalueIsTypeTag => {
            f.push("is_type_tag(");
            write_operand(f, db, r.operand);
            f.push(`, ${type_tag_name(r.tag)})`);
        },
        let r: RvalueMakeClosure => {
            f.push(`make_closure lambda[${r.lambda_idx}]`);
            if (r.type_arg_templates.length() > 0) {
                f.push(`<${r.type_arg_templates.length()} type_args>`);
            }
            f.push("(");
            write_operand_list(f, db, r.captures);
            f.push(")");
        },
        let r: RvalueMakeBoundMethod => {
            f.push(`make_bound_method ${function_display_name(db, r.func)}`);
            match (r.frame) {
                let explicit: BoundFrameExplicit => {
                    f.push(`<${Names.of(db).templates(explicit.value)}>`);
                },
                BoundFrameReceiver => {},
            }
            f.push("(");
            write_operand(f, db, r.receiver);
            f.push(")");
        },
        let r: RvalueMakeVirtualBoundMethod => {
            let names = Names.of(db);
            f.push(`make_virtual_bound_method ${names.interface(r.iface)}.${r.method}`);
            if (r.type_args.length() > 0) {
                f.push(`<${names.templates(r.type_args)}>`);
            }
            f.push("(");
            write_operand(f, db, r.receiver);
            f.push(")");
        },
        let r: RvalueMakeVirtualFunction => {
            f.push(
                `make_virtual_function (${Names.of(db).template(r.self_ty)} as ${Names.of(db).interface(r.iface)}).${r.method}`,
            );
            if (r.type_args.length() > 0) {
                f.push("<");
                write_operand_list(f, db, r.type_args);
                f.push(">");
            }
        },
        let r: RvalueLoadType => {
            f.push(`load_type(${Names.of(db).template(r.value)})`);
        },
        RvalueCurrentPackage => {
            f.push("current_package");
        },
        let r: RvalueMakeGenericFunction => {
            f.push(
                `make_generic_function ${function_display_name(db, r.func)}<${Names.of(db).templates(r.type_arg_templates)}>`,
            );
        },
        let r: RvalueMakeGenericFunctionFromValue => {
            f.push("make_generic_function_from_value(");
            write_operand(f, db, r.value);
            f.push(`)<${Names.of(db).templates(r.type_arg_templates)}>`);
        },
    }
}

// port: baml_compiler2_mir/src/pretty.rs::type_tag_name @ d9be6853b
// Symbolic name for a `baml_type::typetag` constant in `is_type_tag`
// renders. Class tags (`CLASS_BASE + n`) and anything unrecognized print
// numerically. The full tag set is named for robustness, though the only MIR
// producer today (`emit_is_type_tag_branch`) emits `LIST`/`MAP`. The
// constants are written by value (typetag.rs is not ported).
function type_tag_name(tag: int) -> string throws never {
    match (tag) {
        0 => "INT",
        1 => "STRING",
        2 => "BOOL",
        3 => "NULL",
        4 => "FLOAT",
        5 => "ENUM",
        6 => "LIST",
        7 => "MAP",
        8 => "FUNCTION",
        9 => "FUTURE",
        10 => "TYPE",
        12 => "UINT8ARRAY",
        13 => "BIGINT",
        -2 => "PANIC",
        14 => "TUPLE",
        _ => tag.to_string(),
    }
}

// port: baml_compiler2_mir/src/pretty.rs::write_operand @ d9be6853b
function write_operand(f: string[], db: root.hir.Db, operand: Operand) -> void throws never {
    match (operand) {
        let o: OperandCopy => {
            f.push(`copy ${place_to_string(o.value)}`);
        },
        let o: OperandMove => {
            f.push(`move ${place_to_string(o.value)}`);
        },
        let o: OperandConstant => write_constant(f, db, o.value),
    }
}

// port: baml_compiler2_mir/src/pretty.rs::write_constant @ d9be6853b
function write_constant(f: string[], db: root.hir.Db, constant: Constant) -> void throws never {
    match (constant) {
        let c: ConstantInt => {
            f.push(`const ${c.value}_i64`);
        },
        let c: ConstantBigint => {
            f.push(`const ${c.value}n`);
        },
        let c: ConstantFloat => {
            f.push(`const ${rust_float_display(c.value)}_f64`);
        },
        let c: ConstantString => {
            f.push(`const ${root.base.rust_debug_string(c.value)}`);
        },
        let c: ConstantBool => {
            f.push(`const ${c.value}`);
        },
        ConstantNull => {
            f.push("const null");
        },
        ConstantOmittedArg => {
            f.push("const <omitted>");
        },
        let c: ConstantFunction => {
            f.push(`const fn ${function_display_name(db, c.value)}`);
        },
        let c: ConstantGlobalItem => {
            f.push(`const item ${global_display_name(db, c.value)}`);
        },
        let c: ConstantGenericFunction => {
            let spelling = Names.of(db);
            let args = c.type_args.map((ty) -> {
                display_lowering_ty(root.types.widen_realized_ty_to_lowering_ty(ty), spelling)
            });
            f.push(`const fn ${function_display_name(db, c.func)}<${args.join(", ")}>`);
        },
        let c: ConstantEnumVariant => {
            let variants = root.hir_ty.enum_variants(db, root.hir.DeclRefSource { value: c.enum_ref });
            let variant = variants.at(c.index) ?? `#${c.index}`;
            f.push(`const ${enum_display_name(db, c.enum_ref)}.${variant}`);
        },
    }
}
