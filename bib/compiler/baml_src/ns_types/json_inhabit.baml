// port: baml_type/src/json_inhabit.rs @ d9be6853b
//
// Which values of a type can come from JSON.
//
// A JSON reader builds only some values of a type. `uint8array` has no JSON
// form, `never` has no values at all, and a class whose every value is cyclic
// has none that JSON, which holds finite trees only, can carry. Each reader
// drops what it cannot build: `uint8array | string` reads as `string`, an
// optional `uint8array?` field is only `null`, and `never[]` is only `[]`.
//
// JsonInhabitance answers that question once for every reader:
// `baml.json.schema`, the LLM output check, the prompt renderer, and
// schema-aligned parsing. A reader describes its definitions through
// JsonDefs, which also decides the types whose JSON form is the reader's own
// call (`opaque`), and the types a model writes in another form (`shape`).
//
// Rust is generic over the head `H`; every family member here is
// DeclName-headed, so this is the RuntimeTy (DeclName) instantiation the type
// checker uses.
//
// Restructured:
// - `JsonNaming` is an enum, and BAML enums have no methods: its methods are
//   free functions `json_naming_<method>`.
// - JsonDefs's associated `Error` stays an associated type; a function generic
//   over a reader is `<D extends JsonDefs>` and throws `JsonError<D.Error>`.
// - JsonDefs's `check` and `shape` have no default bodies: a default that
//   cannot throw is warned about as `throws Self.Error` (E0097), and a
//   `throws never` default binds every override to `never` (E0120). Each
//   reader writes Rust's default (accept every type; no shape).
// - discover's `Enum | EnumVariant` arm is `discover_enum`, shared by both
//   variants, and its class body is built by `class_body`.
// - `JsonInhabitance::of` only forwards to `of_all` with one root: call
//   `JsonInhabitance.of_all([ty], defs, naming)`.
// - Definition chains are as deep as the input, so the walks that cross
//   definitions do not recurse: `discover` runs a work stack (its `path`
//   parameter, always empty at the start, is per work item),
//   `witness_walk` is a loop (each step is a tail call), and
//   `has_empty_value` folds Rust's recursive `has_empty_value_within` into a
//   stack of EmptyFrames. `status`, `inhabited`, `finite` and `node` still
//   recurse: they stop at a definition, so their depth is one type
//   expression's nesting.
// - JsonInhabitance's `status` and `inhabited` fields clash with its methods
//   of the same names: they are `status_value` and `inhabited_value`.
// - `id_args` is not ported: only a class id has arguments, and every caller
//   holds a DefIdClass, so it reads `id.args`.
// - `Witness::reason` takes a TyRenderStrategy: Rust bounds it by
//   `HeadDisplay`, which DeclName does not implement.
// - Rust's `(String, RuntimeTy)` and `(&H, &str)` pairs are tuples.

// port: baml_type/src/json_inhabit.rs::JsonNaming @ d9be6853b
// Which names a class's fields and an enum's variants go by in JSON: the
// runtime form of `baml.json.Naming`. The JSON Schema `baml.json.schema`
// writes, and the JSON the other `baml.json` conversions read and write, all
// follow it, through json_naming_key and json_naming_shows.
enum JsonNaming {
    // Declared names. `@alias` and `@skip` have no effect: the interchange
    // form of BEP-038.
    Declared,
    // The names a model is shown: a member's `@alias` if it has one, and no
    // `@skip` member at all.
    Aliased,
}

// port: baml_type/src/json_inhabit.rs::JsonNaming::new @ d9be6853b
// `Aliased` when `aliased` holds, else `Declared`.
function json_naming_new(aliased: bool) -> JsonNaming throws never {
    if (aliased) {
        JsonNaming.Aliased
    } else {
        JsonNaming.Declared
    }
}

// port: baml_type/src/json_inhabit.rs::JsonNaming::key @ d9be6853b
// The JSON key of a field, or the JSON string of a variant, declared as
// `name` with `alias` and `rename`. `@json.rename` holds under every naming;
// `@alias` is only the name a model is shown.
function json_naming_key(
    naming: JsonNaming,
    name: string,
    alias: string?,
    rename: string?,
) -> string throws never {
    match (rename) {
        let renamed: string => renamed,
        null => {
            match (naming) {
                JsonNaming.Declared => name,
                JsonNaming.Aliased => alias ?? name,
            }
        },
    }
}

// port: baml_type/src/json_inhabit.rs::JsonNaming::shows @ d9be6853b
// Whether a member with this `@skip` setting appears in JSON at all.
function json_naming_shows(naming: JsonNaming, skip: bool) -> bool throws never {
    match (naming) {
        JsonNaming.Declared => true,
        JsonNaming.Aliased => !skip,
    }
}

// port: baml_type/src/json_inhabit.rs::JsonStatus @ d9be6853b
// What a type's values look like as JSON once the values with no JSON form
// are set aside.
enum JsonStatus {
    // Some values have a JSON form, and a reader builds exactly those.
    Json,
    // The type has values, but none has a JSON form: `uint8array`, a
    // function, a class that requires one, or a class whose every value is
    // cyclic. A union drops it like `never`, but a list or map of it has no
    // JSON form either, rather than being only the empty one.
    NoJson,
    // The type has no values at all: `never`, an enum with no variants, and
    // whatever requires one of them. A list or map of it is only the empty
    // one.
    Empty,
}

// port: baml_type/src/json_inhabit.rs::JsonClass @ d9be6853b
// A class as a reader's definitions describe it, at the type arguments it
// was asked for.
class JsonClass {
    // Every field the class declares, `@skip` ones included, in declaration
    // order.
    fields: JsonField[],
}

// port: baml_type/src/json_inhabit.rs::JsonField @ d9be6853b
// One field of a JsonClass.
class JsonField {
    name: string,
    alias: string?,
    skip: bool,
    ty: RuntimeTy,
}

// port: baml_type/src/json_inhabit.rs::JsonVariant @ d9be6853b
// One variant of an enum, as a reader's definitions describe it.
class JsonVariant {
    name: string,
    skip: bool,
}

// port: baml_type/src/json_inhabit.rs::JsonDefs @ d9be6853b
// The definitions a type reaches, as one reader sees them.
interface JsonDefs {
    // Why a definition cannot be looked up, or why the reader rejects a type.
    type Error;

    // The class `head` instantiated at `args`, its field types realized at
    // those arguments.
    function class_(self, head: DeclName, args: RuntimeTy[]) -> JsonClass throws Self.Error;

    // The variants of the enum `head`, `@skip` ones included, in declaration
    // order.
    function variants(self, head: DeclName) -> JsonVariant[] throws Self.Error;

    // The type the recursive alias `head` stands for.
    function alias_target(self, head: DeclName) -> RuntimeTy throws Self.Error;

    // The status of a type whose JSON form is the reader's own call:
    // `unknown`, an interface, a type parameter or projection, and media. No
    // schema describes the first ones, and a reader may or may not build
    // media. An error stops the analysis.
    function opaque(self, ty: RuntimeTy) -> JsonStatus throws Self.Error;

    // Rejects a type the reader cannot take, wherever the analysis meets it
    // in a part of a value JSON carries. Rust's default accepts every type.
    function check(self, ty: RuntimeTy) -> void throws Self.Error;

    // The type JSON holds in place of `ty`, a class or enum type: its
    // `baml.FromLlmOutput` `Shape`, for a reader of a model's answer. The
    // analysis then gives `ty` the status of that type, and never looks at
    // the fields or variants of `ty`. Rust's default is null: the type is
    // read by its fields or variants.
    function shape(self, ty: RuntimeTy) -> RuntimeTy? throws Self.Error;
}

// port: baml_type/src/json_inhabit.rs::JsonError @ d9be6853b
// Why JsonInhabitance.of_all stopped: a reader's error, and where the
// analysis met it.
class JsonError<E> {
    error: E,
    // The declared names of the fields from the root type down to the type
    // the error is about. Empty when it is about the root itself.
    path: string[],
}

// port: baml_type/src/json_inhabit.rs::DefId @ d9be6853b
// A class instantiation, recursive alias, or shaped enum: a definition the
// analysis gives one status, whose body can reach itself.
type DefId = DefIdClass | DefIdAlias | DefIdEnum;

// Each argument's union is spelled flat, so `Box<(int | null) | null>` and
// `Box<int | null>` are one definition (build it with def_id_class).
class DefIdClass {
    head: DeclName,
    args: RuntimeTy[],
}

class DefIdAlias {
    head: DeclName,
}

// An enum the reader gives a shape (JsonDefs.shape). Any other enum is a
// leaf, not a definition.
class DefIdEnum {
    head: DeclName,
}

// port: baml_type/src/json_inhabit.rs::DefId::class @ d9be6853b
function def_id_class(head: DeclName, args: RuntimeTy[]) -> DefIdClass throws never {
    DefIdClass { head: head, args: args.map(flatten_union_runtime_ty) }
}

// port: baml_type/src/json_inhabit.rs::DefId::head @ d9be6853b
function def_id_head(id: DefId) -> DeclName throws never {
    match (id) {
        let c: DefIdClass => c.head,
        let a: DefIdAlias => a.head,
        let e: DefIdEnum => e.head,
    }
}

// port: baml_type/src/json_inhabit.rs::ClassBody @ d9be6853b
// A class's fields as JSON shows them under the analysis's JsonNaming.
class ClassBody {
    // The fields JSON carries, each with its declared name, in declaration
    // order.
    fields: (string, RuntimeTy)[],
    // The first field JSON leaves out (`@skip`, under aliased names) whose
    // type has no empty value, with that type. A field JSON leaves out holds
    // its type's empty value, so with none to hold, the class has no JSON
    // form.
    unfillable: (string, RuntimeTy)?,
}

// port: baml_type/src/json_inhabit.rs::DefBody @ d9be6853b
type DefBody = DefBodyClass | DefBodyAlias | DefBodyShaped;

class DefBodyClass {
    value: ClassBody,
}

class DefBodyAlias {
    value: RuntimeTy,
}

// A class or enum JSON holds as this type instead (JsonDefs.shape): it has
// the status of that type.
class DefBodyShaped {
    value: RuntimeTy,
}

// port: baml_type/src/json_inhabit.rs::Node @ d9be6853b
// One level of a type, as the analysis sees it. JsonInhabitance.node is the
// one place that matches on RuntimeTy for the fixpoints.
type Node = NodeLeaf | NodeNoJson | NodeNever | NodeUnion | NodeContainer | NodeProduct | NodeDef;

// A type whose every value has a JSON form.
class NodeLeaf {
}

// A type none of whose values has a JSON form.
class NodeNoJson {
}

// A type with no values.
class NodeNever {
}

// A union's members, nested unions flattened.
class NodeUnion {
    value: RuntimeTy[],
}

// A list's element or a map's value.
class NodeContainer {
    value: RuntimeTy,
}

class NodeProduct {
    value: RuntimeTy[],
}

class NodeDef {
    value: DefId,
}

// port: baml_type/src/json_inhabit.rs::JsonInhabitance @ d9be6853b
// The JsonStatus of every class instantiation and recursive alias some root
// types reach, under one JsonNaming.
//
// The statuses are fixpoints over the definition graph, computed in two
// steps. Which definitions are `Empty` is the greatest fixpoint of "has a
// value": a cycle through fields does not empty a class, because a BAML value
// can be cyclic. The rest are `Json` unless something forces `NoJson`: a
// field that requires a value with no JSON form, or having only cyclic
// values. JSON holds finite trees only, so a definition must also have a
// finite value (the least fixpoint, where an empty list or map is always
// finite), and one that has none becomes `NoJson`, which can force others in
// turn.
//
// Only the parts of a value JSON carries are looked at: the fields a naming
// shows, and every union member. A field JSON leaves out only needs an empty
// value to hold.
class JsonInhabitance {
    naming: JsonNaming,
    // Every definition the roots reach, in the order they reach them.
    ids: DefId[],
    index: map<DefId, int>,
    bodies: DefBody[],
    // Rust's `status` (renamed: it clashes with the method).
    status_value: JsonStatus[],
    // Whether each definition has a value; final before `status_value` is.
    // Rust's `inhabited` (renamed: it clashes with the method).
    inhabited_value: bool[],
    variants: map<DeclName, JsonVariant[]>,
    opaque: map<RuntimeTy, JsonStatus>,

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::of_all @ d9be6853b
    // The analysis of everything any of `roots` reaches. Throws the first
    // error `defs` reports on the way, with the fields that lead to it from
    // the root it was met under.
    function of_all<D extends JsonDefs>(
        roots: RuntimeTy[],
        defs: D,
        naming: JsonNaming,
    ) -> JsonInhabitance throws JsonError<D.Error> {
        let analysis = JsonInhabitance {
            naming: naming,
            ids: [],
            index: {},
            bodies: [],
            status_value: [],
            inhabited_value: [],
            variants: {},
            opaque: {},
        };
        for (let ty in roots) {
            analysis.discover(ty, defs);
        }
        analysis.solve();
        analysis
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::status @ d9be6853b
    // The status of `ty`, a type the roots reach. A type the analysis has not
    // seen is taken to be `Json`.
    function status(self, ty: RuntimeTy) -> JsonStatus {
        if (!self.inhabited(ty)) {
            return JsonStatus.Empty;
        }
        match (self.node(ty)) {
            NodeLeaf => JsonStatus.Json,
            NodeNoJson => JsonStatus.NoJson,
            NodeNever => JsonStatus.Empty,
            let u: NodeUnion => {
                if (
                    u.value.some((member) -> {
                        self.status(member) == JsonStatus.Json
                    })
                ) {
                    JsonStatus.Json
                } else {
                    JsonStatus.NoJson
                }
            },
            let c: NodeContainer => {
                match (self.status(c.value)) {
                    JsonStatus.Json | JsonStatus.Empty => JsonStatus.Json,
                    JsonStatus.NoJson => JsonStatus.NoJson,
                }
            },
            let p: NodeProduct => {
                if (
                    p.value.every((element) -> {
                        self.status(element) == JsonStatus.Json
                    })
                ) {
                    JsonStatus.Json
                } else {
                    JsonStatus.NoJson
                }
            },
            let d: NodeDef => self.def_status(d.value),
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::witness @ d9be6853b
    // Why `ty`, a `NoJson` or `Empty` type, has no value with a JSON form:
    // the fields that lead to the cause, and the cause. A union leads through
    // its first member of the same status.
    function witness(self, ty: RuntimeTy) -> Witness {
        let path: (DeclName, string)[] = [];
        let cause = self.witness_walk(ty, path, {});
        Witness { path: path, cause: cause }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::witness_walk @ d9be6853b
    // Restructured: every step of Rust's recursion is a tail call, so it is a
    // loop over the current type.
    function witness_walk(
        self,
        ty: RuntimeTy,
        path: (DeclName, string)[],
        seen: map<int, bool>,
    ) -> WitnessCause {
        let current = ty;
        while (true) {
            let status = self.status(current);
            // The member, element or field to blame: the first that is
            // uninhabited when `current` is `Empty`, else the first with no
            // JSON form.
            let blamed = (t: RuntimeTy) -> bool {
                if (status == JsonStatus.Empty) {
                    !self.inhabited(t)
                } else {
                    self.status(t) == JsonStatus.NoJson
                }
            };
            let next: RuntimeTy? = match (self.node(current)) {
                NodeLeaf | NodeNoJson | NodeNever => null,
                let u: NodeUnion => {
                    u.value.find((member) -> {
                        self.status(member) == status
                    })
                },
                let c: NodeContainer => c.value,
                let p: NodeProduct => p.value.find(blamed),
                let d: NodeDef => {
                    let at = self.index.get(d.value)
                        ?? return WitnessCauseLeaf { value: current };
                    let head = def_id_head(self.ids[at]);
                    if (seen.has(at)) {
                        return WitnessCauseCyclic { head: head, revisited: true };
                    }
                    seen.set(at, true);
                    match (self.bodies[at]) {
                        let b: DefBodyClass => {
                            let unfillable = b.value.unfillable;
                            if (status != JsonStatus.Empty && unfillable != null) {
                                return WitnessCauseUnfillable {
                                    class_: head,
                                    field: unfillable.0,
                                    ty: unfillable.1,
                                };
                            }
                            let culprit = b.value.fields.find((field) -> {
                                blamed(field.1)
                            })
                                ?? return WitnessCauseCyclic { head: head, revisited: false };
                            path.push((head, culprit.0));
                            culprit.1
                        },
                        let a: DefBodyAlias => a.value,
                        let s: DefBodyShaped => s.value,
                    }
                },
            };
            current
                = next
                    ?? return WitnessCauseLeaf { value: current };
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::discover @ d9be6853b
    // Records every definition `ty` reaches, with its body, and asks `defs`
    // about every type on the way. Fields the naming leaves out are not
    // visited.
    // Restructured: a work stack of (type, path) pairs, popped in the order
    // Rust's recursion visits them, so the same error is the first met.
    function discover<D extends JsonDefs>(
        self,
        ty: RuntimeTy,
        defs: D,
    ) -> void throws JsonError<D.Error> {
        let work: (RuntimeTy, string[])[] = [(ty, [])];
        // Queues `tys` so that the first is visited first.
        let visit_all = (tys: RuntimeTy[], path: string[]) -> void {
            for (let i = tys.length() - 1; i >= 0; i -= 1) {
                work.push((tys[i], path));
            }
        };
        while let item: (RuntimeTy, string[]) = work.pop() {
            let (let t, let path) = item;
            defs.check(t) catch (e) {
                _ => throw JsonError { error: e, path: path },
            };
            match (t) {
                TyUnknown
                    | RuntimeTyInterface
                    | TyTypeVar
                    | RuntimeTyAssociatedTypeProjection
                    | TyMedia =>
                {
                    if (!self.opaque.has(t)) {
                        let status = defs.opaque(t) catch (e) {
                            _ => throw JsonError { error: e, path: path },
                        };
                        self.opaque.set(t, status);
                    }
                },
                let e: TyEnum => self.discover_enum(e.name, path, defs, work),
                let v: TyEnumVariant => self.discover_enum(v.name, path, defs, work),
                let u: RuntimeTyUnion => {
                    let flat: RuntimeTy[] = [];
                    flatten_union(u.members, flat);
                    visit_all(flat, path)
                },
                let l: RuntimeTyList => {
                    work.push((l.elem, path));
                },
                let m: RuntimeTyMap => {
                    work.push((m.value, path));
                },
                let x: RuntimeTyTuple => visit_all(x.items, path),
                let c: RuntimeTyClass => {
                    let id = def_id_class(c.name, c.args);
                    if (!self.index.has(id)) {
                        let class_ty = RuntimeTyClass { name: c.name, args: id.args };
                        let shape = defs.shape(class_ty) catch (e) {
                            _ => throw JsonError { error: e, path: path },
                        };
                        if (shape != null) {
                            self.insert(id, DefBodyShaped { value: shape });
                            work.push((shape, path));
                        } else {
                            let body = self.class_body(c.name, id.args, path, defs);
                            self.insert(id, DefBodyClass { value: body });
                            for (let i = body.fields.length() - 1; i >= 0; i -= 1) {
                                let field = body.fields[i];
                                work.push((field.1, path.concat([field.0])));
                            }
                        }
                    }
                },
                let a: TyTypeAlias => {
                    let id = DefIdAlias { head: a.name };
                    if (!self.index.has(id)) {
                        let target = defs.alias_target(a.name) catch (e) {
                            _ => throw JsonError { error: e, path: path },
                        };
                        self.insert(id, DefBodyAlias { value: target });
                        work.push((target, path));
                    }
                },
                TyInt
                    | TyBigint
                    | TyFloat
                    | TyString
                    | TyBool
                    | TyNull
                    | TyLiteral
                    | TyUint8Array
                    | RuntimeTyFunction
                    | RuntimeTyFuture
                    | TyRustType
                    | TyType
                    | TyResource
                    | TyPromptAst
                    | TyNever =>
                {},
            }
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::discover @ d9be6853b
    // discover's `Enum | EnumVariant` arm, shared by both variants.
    function discover_enum<D extends JsonDefs>(
        self,
        head: DeclName,
        path: string[],
        defs: D,
        work: (RuntimeTy, string[])[],
    ) -> void throws JsonError<D.Error> {
        let id = DefIdEnum { head: head };
        if (self.index.has(id) || self.variants.has(head)) {
            return;
        }
        // A variant type of a shaped enum stays a variant: only the enum
        // itself is written as its shape.
        let shape = defs.shape(TyEnum { name: head }) catch (e) {
            _ => throw JsonError { error: e, path: path },
        };
        if (shape != null) {
            self.insert(id, DefBodyShaped { value: shape });
            work.push((shape, path));
            return;
        }
        let variants = defs.variants(head) catch (e) {
            _ => throw JsonError { error: e, path: path },
        };
        self.variants.set(head, variants);
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::discover @ d9be6853b
    // discover's `Class` arm once no shape applies: the class's body under
    // the analysis's naming.
    function class_body<D extends JsonDefs>(
        self,
        head: DeclName,
        args: RuntimeTy[],
        path: string[],
        defs: D,
    ) -> ClassBody throws JsonError<D.Error> {
        let class_ = defs.class_(head, args) catch (e) {
            _ => throw JsonError { error: e, path: path },
        };
        let fields: (string, RuntimeTy)[] = [];
        let unfillable: (string, RuntimeTy)? = null;
        for (let field in class_.fields) {
            if (json_naming_shows(self.naming, field.skip)) {
                fields.push((field.name, field.ty));
            } else if (unfillable == null) {
                let has = has_empty_value(defs, field.ty) catch (e) {
                    _ => throw JsonError { error: e, path: path.concat([field.name]) },
                };
                if (!has) {
                    unfillable = (field.name, field.ty);
                }
            }
        }
        ClassBody { fields: fields, unfillable: unfillable }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::insert @ d9be6853b
    function insert(self, id: DefId, body: DefBody) -> int {
        let at = self.ids.length();
        self.index.set(id, at);
        self.ids.push(id);
        self.bodies.push(body);
        // Provisional; `solve` computes the real values.
        self.status_value.push(JsonStatus.Json);
        self.inhabited_value.push(true);
        at
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::solve @ d9be6853b
    function solve(self) -> void {
        let count = self.ids.length();

        // Greatest fixpoint of "has a value": start from every definition
        // having one, and clear the ones that cannot.
        let changed = true;
        while (changed) {
            changed = false;
            for (let at = 0; at < count; at += 1) {
                if (self.inhabited_value[at] && !self.body_inhabited(at)) {
                    self.inhabited_value[at] = false;
                    changed = true;
                }
            }
        }
        for (let at = 0; at < count; at += 1) {
            self.status_value[at]
                = if (self.inhabited_value[at]) {
                    JsonStatus.Json
                } else {
                    JsonStatus.Empty
                };
        }

        while (true) {
            // Greatest fixpoint of `Json` among the inhabited definitions.
            changed = true;
            while (changed) {
                changed = false;
                for (let at = 0; at < count; at += 1) {
                    if (
                        self.status_value[at] == JsonStatus.Json
                            && self.body_status(at) == JsonStatus.NoJson
                    ) {
                        self.status_value[at] = JsonStatus.NoJson;
                        changed = true;
                    }
                }
            }
            // Least fixpoint of "has a finite value" among the `Json`
            // definitions. One with none has only cyclic values.
            let finite: bool[] = baml.Array.filled(count, false);
            changed = true;
            while (changed) {
                changed = false;
                for (let at = 0; at < count; at += 1) {
                    if (
                        self.status_value[at] == JsonStatus.Json
                            && !finite[at]
                            && self.body_finite(at, finite)
                    ) {
                        finite[at] = true;
                        changed = true;
                    }
                }
            }
            let cyclic: int[] = [];
            for (let at = 0; at < count; at += 1) {
                if (self.status_value[at] == JsonStatus.Json && !finite[at]) {
                    cyclic.push(at);
                }
            }
            if (!cyclic) {
                break;
            }
            for (let at in cyclic) {
                self.status_value[at] = JsonStatus.NoJson;
            }
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::node @ d9be6853b
    function node(self, ty: RuntimeTy) -> Node {
        match (ty) {
            TyInt | TyBigint | TyFloat | TyString | TyBool | TyNull | TyLiteral => NodeLeaf {},
            let e: TyEnum => {
                let id = DefIdEnum { head: e.name };
                if (self.index.has(id)) {
                    return NodeDef { value: id };
                }
                let variants = self.variants.get(e.name)
                    ?? return NodeLeaf {};
                if (!variants) {
                    NodeNever {}
                } else if (
                    !variants.some((variant) -> {
                        json_naming_shows(self.naming, variant.skip)
                    })
                ) {
                    // Every variant `@skip` under aliased names: values
                    // exist, but JSON names none of them.
                    NodeNoJson {}
                } else {
                    NodeLeaf {}
                }
            },
            let v: TyEnumVariant => {
                let variants = self.variants.get(v.name);
                let shown = variants == null
                    || variants.some((variant) -> {
                        variant.name == v.variant && json_naming_shows(self.naming, variant.skip)
                    });
                if (shown) {
                    NodeLeaf {}
                } else {
                    NodeNoJson {}
                }
            },
            TyNever => NodeNever {},
            TyUint8Array
                | RuntimeTyFunction
                | RuntimeTyFuture
                | TyRustType
                | TyType
                | TyResource
                | TyPromptAst =>
            {
                NodeNoJson {}
            },
            TyUnknown | RuntimeTyInterface | TyTypeVar | RuntimeTyAssociatedTypeProjection | TyMedia => {
                match (self.opaque.get(ty)) {
                    JsonStatus.NoJson => NodeNoJson {},
                    JsonStatus.Empty => NodeNever {},
                    JsonStatus.Json | null => NodeLeaf {},
                }
            },
            let u: RuntimeTyUnion => {
                let flat: RuntimeTy[] = [];
                flatten_union(u.members, flat);
                NodeUnion { value: flat }
            },
            let l: RuntimeTyList => NodeContainer { value: l.elem },
            let m: RuntimeTyMap => NodeContainer { value: m.value },
            let x: RuntimeTyTuple => NodeProduct { value: x.items },
            let c: RuntimeTyClass => NodeDef { value: def_id_class(c.name, c.args) },
            let a: TyTypeAlias => NodeDef { value: DefIdAlias { head: a.name } },
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::def_status @ d9be6853b
    function def_status(self, id: DefId) -> JsonStatus {
        let at = self.index.get(id)
            ?? return JsonStatus.Json;
        self.status_value[at]
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::inhabited @ d9be6853b
    // Whether `ty` has any value at all, JSON or not.
    function inhabited(self, ty: RuntimeTy) -> bool {
        match (self.node(ty)) {
            NodeLeaf | NodeNoJson | NodeContainer => true,
            NodeNever => false,
            let u: NodeUnion => {
                u.value.some((member) -> {
                    self.inhabited(member)
                })
            },
            let p: NodeProduct => {
                p.value.every((element) -> {
                    self.inhabited(element)
                })
            },
            let d: NodeDef => {
                let at = self.index.get(d.value)
                    ?? return true;
                self.inhabited_value[at]
            },
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::body_inhabited @ d9be6853b
    function body_inhabited(self, at: int) -> bool {
        match (self.bodies[at]) {
            let b: DefBodyClass => {
                b.value.fields.every((field) -> {
                    self.inhabited(field.1)
                })
            },
            let a: DefBodyAlias => self.inhabited(a.value),
            let s: DefBodyShaped => self.inhabited(s.value),
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::body_status @ d9be6853b
    function body_status(self, at: int) -> JsonStatus {
        match (self.bodies[at]) {
            let b: DefBodyClass => {
                if (b.value.unfillable != null) {
                    return JsonStatus.NoJson;
                }
                if (
                    b.value.fields.every((field) -> {
                        self.status(field.1) == JsonStatus.Json
                    })
                ) {
                    JsonStatus.Json
                } else {
                    JsonStatus.NoJson
                }
            },
            let a: DefBodyAlias => self.status(a.value),
            let s: DefBodyShaped => self.status(s.value),
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::finite @ d9be6853b
    // Whether `ty`, a `Json` type, has a finite JSON value, given the
    // definitions known to have one.
    function finite(self, ty: RuntimeTy, finite: bool[]) -> bool {
        match (self.node(ty)) {
            NodeLeaf | NodeContainer => true,
            NodeNoJson | NodeNever => false,
            let u: NodeUnion => {
                u.value.some((member) -> {
                    self.status(member) == JsonStatus.Json && self.finite(member, finite)
                })
            },
            let p: NodeProduct => {
                p.value.every((element) -> {
                    self.finite(element, finite)
                })
            },
            let d: NodeDef => {
                let at = self.index.get(d.value)
                    ?? return true;
                finite[at]
            },
        }
    }

    // port: baml_type/src/json_inhabit.rs::JsonInhabitance::body_finite @ d9be6853b
    function body_finite(self, at: int, finite: bool[]) -> bool {
        match (self.bodies[at]) {
            let b: DefBodyClass => {
                b.value.unfillable == null
                    && b.value.fields.every((field) -> {
                        self.finite(field.1, finite)
                    })
            },
            let a: DefBodyAlias => self.finite(a.value, finite),
            let s: DefBodyShaped => self.finite(s.value, finite),
        }
    }
}

// port: baml_type/src/json_inhabit.rs::Witness @ d9be6853b
// Why a type has no value with a JSON form (JsonInhabitance.witness).
class Witness {
    // The fields from the type down to the cause: each field's class, and the
    // field's declared name.
    path: (DeclName, string)[],
    cause: WitnessCause,

    // port: baml_type/src/json_inhabit.rs::Witness::reason @ d9be6853b
    // The witness in words, as `baml.json.schema` reports it: one
    // "field `Class.name`: " per step, then the cause.
    // Restructured: heads and types render through `s` (Rust: HeadDisplay
    // and Display).
    function reason(self, s: TyRenderStrategy) -> string {
        let out = self.path.map((step) -> {
            `field \`${s.qtn(step.0)}.${step.1}\`: `
        });
        out.push(
            match (self.cause) {
                let leaf: WitnessCauseLeaf => {
                    `\`${render_with(widen_runtime_ty_to_lowering_ty(leaf.value), s)}\` has no JSON form`
                },
                let u: WitnessCauseUnfillable => {
                    `field \`${s.qtn(u.class_)}.${u.field}\` is \`@skip\`, so JSON leaves it out, and its type has no empty value to hold`
                },
                let c: WitnessCauseCyclic => {
                    let cyclic = `every value of \`${s.qtn(c.head)}\` is cyclic`;
                    if (c.revisited) {
                        cyclic
                    } else {
                        `${cyclic}, and JSON holds only finite values`
                    }
                },
            },
        );
        out.join("")
    }
}

// port: baml_type/src/json_inhabit.rs::WitnessCause @ d9be6853b
// What a Witness leads to.
type WitnessCause = WitnessCauseLeaf | WitnessCauseUnfillable | WitnessCauseCyclic;

// A type with no JSON form at all, such as `uint8array`, or with no values,
// such as `never`.
class WitnessCauseLeaf {
    value: RuntimeTy,
}

// `field` of `class_`, which JSON leaves out (`@skip`, under aliased names),
// has type `ty`, which has no empty value for it to hold. Rust's `class`.
class WitnessCauseUnfillable {
    class_: DeclName,
    field: string,
    ty: RuntimeTy,
}

// Every value of the class or alias `head` is cyclic. `revisited` when the
// path met `head` again, rather than ending at a body that names no other
// cause.
class WitnessCauseCyclic {
    head: DeclName,
    revisited: bool,
}

// port: baml_type/src/json_inhabit.rs::has_empty_value_within @ d9be6853b
// One open call of Rust's recursive `has_empty_value_within`, as a frame of
// has_empty_value's work stack: the types whose answers it combines, and
// which comes next.
class EmptyFrame {
    children: RuntimeTy[],
    next: int,
    // A union, which has an empty value when any child does; otherwise every
    // child must have one.
    any: bool,
    // The class or alias this frame put on `within`.
    pushed: DefId?,
}

// port: baml_type/src/json_inhabit.rs::has_empty_value @ d9be6853b
// Whether `ty` has an empty value: the value a `@skip` field holds when JSON
// is read under aliased names. The VM builds that value (`bex_vm`'s
// `sap::empty_value`); this is the same rule as a predicate: `null` for a
// nullable type, zeroes, `false`, `""`, empty containers, a literal's own
// value, an enum's first variant that is not `@skip`, and a class whose
// fields all have one. A class or alias that needs its own empty value has
// none. Throws for a definition `defs` cannot look up.
// Restructured: Rust's recursive `has_empty_value_within` is folded in as a
// walk over a stack of EmptyFrames; `within` holds the definitions of the
// open frames.
function has_empty_value<D extends JsonDefs>(defs: D, ty: RuntimeTy) -> bool throws D.Error {
    let within: DefId[] = [];
    let frames: EmptyFrame[] = [];
    // A leaf's answer, or the frame that combines a compound type's parts.
    let open = (t: RuntimeTy) -> bool | EmptyFrame {
        match (t) {
            TyNull
                | TyUnknown
                | TyInt
                | TyBigint
                | TyFloat
                | TyBool
                | TyString
                | TyUint8Array
                | TyLiteral
                | RuntimeTyList
                | RuntimeTyMap =>
            {
                true
            },
            let e: TyEnum => {
                defs.variants(e.name).some((variant) -> {
                    !variant.skip
                })
            },
            let v: TyEnumVariant => {
                defs.variants(v.name).some((variant) -> {
                    variant.name == v.variant
                })
            },
            let u: RuntimeTyUnion => {
                if (
                    u.members.some((member) -> {
                        member is TyNull
                    })
                ) {
                    true
                } else {
                    EmptyFrame { children: u.members, next: 0, any: true, pushed: null }
                }
            },
            let c: RuntimeTyClass => {
                let id = def_id_class(c.name, c.args);
                if (within.includes(id)) {
                    return false;
                }
                let class_ = defs.class_(c.name, id.args);
                within.push(id);
                EmptyFrame {
                    children: class_.fields.map((field) -> {
                        field.ty
                    }),
                    next: 0,
                    any: false,
                    pushed: id,
                }
            },
            let x: RuntimeTyTuple => {
                EmptyFrame { children: x.items, next: 0, any: false, pushed: null }
            },
            let a: TyTypeAlias => {
                let id = DefIdAlias { head: a.name };
                if (within.includes(id)) {
                    return false;
                }
                let target = defs.alias_target(a.name);
                within.push(id);
                EmptyFrame { children: [target], next: 0, any: false, pushed: id }
            },
            TyMedia
                | RuntimeTyFunction
                | RuntimeTyFuture
                | RuntimeTyInterface
                | TyRustType
                | TyType
                | TyResource
                | TyPromptAst
                | TyNever
                | TyTypeVar
                | RuntimeTyAssociatedTypeProjection =>
            {
                false
            },
        }
    };
    // Closes the innermost frame.
    let close = () -> void {
        let frame = frames.pop();
        if (frame?.pushed != null) {
            within.pop();
        }
    };
    let result = open(ty);
    while (true) {
        match (result) {
            let frame: EmptyFrame => {
                frames.push(frame);
            },
            let answer: bool => {
                let top = frames.at(frames.length() - 1)
                    ?? return answer;
                // An answer that settles the frame: a union child with an
                // empty value, or a class, tuple or alias part without one.
                if (answer == top.any) {
                    close();
                    continue;
                }
            },
        }
        let top = frames[frames.length() - 1];
        if (top.next < top.children.length()) {
            let child = top.children[top.next];
            top.next += 1;
            result = open(child);
        } else {
            close();
            result = !top.any;
        }
    }
}

// port: baml_type/src/json_inhabit.rs::flatten_union @ d9be6853b
// The members of a union, nested unions spliced in.
function flatten_union(members: RuntimeTy[], out: RuntimeTy[]) -> void {
    for (let member in members) {
        match (member) {
            let nested: RuntimeTyUnion => flatten_union(nested.members, out),
            _ => {
                out.push(member);
            },
        }
    }
}
