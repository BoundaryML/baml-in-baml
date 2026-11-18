// port: baml_tests/src/compiler2_mir/escape.rs @ d9be6853b
//
// Thread-locality classification (`root.mir.analyze`).
//
// Each test lowers one function and checks, per named local, whether every
// object it can hold is thread-local. A wrong `true` is a data race once a
// backend drops the lock, so most cases pin down a way an object leaves.
//
// Restructured:
// - Rust's `make_db()` (a stdlib Db plus a workspace root) is `make_db`,
//   returning a `TestDb`: the Db, its workspace root, and `file` /
//   `dependency` (Rust's `TestDbExt`). Each test builds its own Db, as in
//   Rust.
// - Rust's `r#"\n...\n"#` sources are backtick strings, which drop the
//   leading and trailing newline and the common indentation; `format!`
//   with `{LEAK}` / `{MASKED}` is `${LEAK}` / `${MASKED}`.
// - A locality mask is a `bigint` (as in `root.mir.EscapeFacts`), so
//   `0b01` is `1n` and `escape::NEVER` is `root.mir.NEVER`.
// - `assert_locality`'s message is folded into the compared strings
//   (`<name> thread-local=<bool>`), since BAML's asserts take no message.
// - `review_summary_invalidates_when_callee_starts_spawning` edits the
//   file through salsa (`set_text`); with no incrementality here it
//   classifies the edited source on a fresh Db.
//
// Not ported:
// - `escape_coverage`: an ignored report (`#[ignore]`) over the speedtest
//   workloads, the repository's examples and compiled bytecode, not a
//   check.
// - `bytecode_takes_the_lock_free_paths_for_thread_local_arrays`,
//   `..._maps`, `bytecode_takes_relaxed_field_paths_for_thread_local_instances`,
//   `bytecode_keeps_container_and_field_locks_at_o0`: they compile to
//   bytecode (emit is not ported).
// - `builtin_effects_match_native_signatures`: it compares `EFFECTS` with
//   `baml_builtins2_codegen::extract_native_builtins_for`, which is not
//   ported.
// - `observed_array_iterator_keeps_its_object`: its `array_walks` half is
//   ported; its bytecode half is not.

// port: baml_tests/src/compiler2_mir/mod.rs::make_db @ d9be6853b
// A stdlib Db with a workspace root, and Rust's `TestDbExt` on it.
class TestDb {
    db: root.hir.Db,
    workspace: int,

    // port: baml_db/src/testing.rs::TestDbExt::file @ d9be6853b
    // Add the file at `path`, owned by the root whose path is the longest
    // prefix of `path`; a path under no root goes to the workspace root.
    // Restructured: no update of an existing file (no test needs one).
    function file(self, path: string, text: string) -> int throws never {
        let owner = self.workspace;
        let longest = 0;
        for (let source_root in self.db.roots) {
            let prefix = `${source_root.path}/`;
            if (source_root.path != "" && path.starts_with(prefix) && prefix.length() > longest) {
                owner = source_root.id;
                longest = prefix.length();
            }
        }
        root.db.add_file(self.db, owner, path, text)
    }

    // port: baml_db/src/testing.rs::TestDbExt::dependency @ d9be6853b
    // A source-bearing `Dependency` root for `package` at
    // `<builtin>/<package>`, which the workspace reaches by the edge
    // `package`.
    function dependency(self, package: string) -> int throws never {
        let dependency = root.db.add_root(
            self.db,
            `<builtin>/${package}`,
            root.base.SourceRootKind.Dependency,
            package,
            [],
        );
        self.db.source_root(self.workspace).dependencies.push(
            root.base.Dependency { name: package, root: dependency },
        );
        dependency
    }
}

// port: baml_tests/src/compiler2_mir/mod.rs::make_db @ d9be6853b
function make_db() -> TestDb throws never {
    let db = root.stdlib_db();
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    TestDb { db: db, workspace: workspace }
}

// port: baml_db/src/testing.rs::assert_no_diagnostic_errors @ d9be6853b
// Panics on any error diagnostic of the test's own packages (every root
// that is not the stdlib).
function assert_no_diagnostic_errors(t: TestDb) -> void throws never {
    let errors: string[] = [];
    for (let source_root in t.db.roots) {
        if (source_root.kind == root.base.SourceRootKind.Stdlib) {
            continue;
        }
        let diagnostics = source_root.files
            .flat_map((file) -> {
                root.check_file(t.db, file)
            })
            .concat(root.package_level_diagnostics(t.db, source_root.id));
        for (let diagnostic in diagnostics) {
            if (diagnostic.severity == "error") {
                errors.push(diagnostic.headline);
            }
        }
    }
    if (errors.length() != 0) {
        baml.sys.panic(`unexpected diagnostic errors:\n${errors.join("\n")}`);
    }
}

// The bytecode body of `function_` in `file`, at `opt`, and its arity.
// Not in Rust: the lookup and lowering `classify_file_at_opt`, `needs` and
// `observed_array_iterator_keeps_its_object` each write out.
function lower_named(
    t: TestDb,
    file: int,
    function_: string,
    opt: root.mir.OptLevel,
) -> (root.mir.MirFunctionBody, int) throws never {
    assert_no_diagnostic_errors(t);
    let loc = root.hir.file_functions(t.db, file).find((loc) -> {
        root.hir.function_data(t.db, loc).name == function_
    })
        ?? baml.sys.panic(`no function \`${function_}\``);
    let mir = root.mir.lower_function(t.db, loc, opt) catch (e) {
        root.mir.MirInternalError => baml.sys.panic(`MIR lowering failed: ${e.message}`),
    };
    let body = match (mir.kind) {
        let b: root.mir.MirFunctionKindBytecode => b.value,
        root.mir.MirFunctionKindBuiltin => baml.sys.panic(`\`${function_}\` must lower to bytecode`),
    };
    (body, mir.arity)
}

// port: baml_tests/src/compiler2_mir/escape.rs::classify @ d9be6853b
// `(local name, thread-local)` for each named local of `function_`, in
// declaration order. A shadowed name reports its first declaration.
function classify(source: string, function_: string) -> (string, bool)[] throws never {
    let t = make_db();
    let file = t.file("test.baml", source);
    classify_file(t, file, function_)
}

// port: baml_tests/src/compiler2_mir/escape.rs::classify_file @ d9be6853b
function classify_file(t: TestDb, file: int, function_: string) -> (string, bool)[] throws never {
    classify_file_at_opt(t, file, function_, root.mir.OptLevel.Two)
}

// port: baml_tests/src/compiler2_mir/escape.rs::classify_file_at_opt @ d9be6853b
function classify_file_at_opt(
    t: TestDb,
    file: int,
    function_: string,
    opt: root.mir.OptLevel,
) -> (string, bool)[] throws never {
    let (let body, let arity) = lower_named(t, file, function_, opt);
    let facts = root.mir.analyze(t.db, t.db.file(file).root, body, arity, opt);
    let seen: map<string, bool> = {};
    let out: (string, bool)[] = [];
    for (let index = 0; index < body.locals.length(); index += 1) {
        let name = body.locals[index].name;
        if (name == null || seen.has(name)) {
            continue;
        }
        seen[name] = true;
        out.push((name, facts.local_is_thread_local(index)));
    }
    out
}

// port: baml_tests/src/compiler2_mir/escape.rs::needs @ d9be6853b
// For each named local of `function_`, the parameters it is thread-local
// given (`EscapeFacts.object_needs`); and for each call to a source
// function, in block order, its arguments' needs.
function needs(source: string, function_: string) -> ((string, bigint)[], bigint[][]) throws never {
    let t = make_db();
    let file = t.file("test.baml", source);
    let (let body, let arity) = lower_named(t, file, function_, root.mir.OptLevel.Two);
    let facts = root.mir.analyze(t.db, t.db.file(file).root, body, arity, root.mir.OptLevel.Two);
    let seen: map<string, bool> = {};
    let locals: (string, bigint)[] = [];
    for (let index = 0; index < body.locals.length(); index += 1) {
        let name = body.locals[index].name;
        if (name == null || seen.has(name)) {
            continue;
        }
        seen[name] = true;
        locals.push((name, facts.object_needs(root.mir.PlaceLocal { value: index })));
    }
    let calls: bigint[][] = [];
    for (let block = 0; block < body.blocks.length(); block += 1) {
        let args = facts.call_arg_needs(block);
        if (args != null) {
            calls.push(args);
        }
    }
    (locals, calls)
}

// port: baml_tests/src/compiler2_mir/escape.rs::assert_locality @ d9be6853b
function assert_locality(
    source: string,
    function_: string,
    expected: (string, bool)[],
) -> void throws never {
    let actual = classify(source, function_);
    for (let entry in expected) {
        let (let name, let local) = entry;
        let found = actual.find((a) -> {
            a.0 == name
        })
            ?? baml.sys.panic(`no local \`${name}\` in ${actual}`);
        assert.equal(`${name} thread-local=${found.1}`, `${name} thread-local=${local}`);
    }
}

// The named local's entry of `needs`' locals.
// Not in Rust: the `locals.iter().find(..).unwrap().1` the tests repeat.
function needs_of(locals: (string, bigint)[], name: string) -> bigint throws never {
    let found = locals.find((entry) -> {
        entry.0 == name
    })
        ?? baml.sys.panic(`no local \`${name}\``);
    found.1
}

// port: baml_tests/src/compiler2_mir/escape.rs::LEAK @ d9be6853b
// Leaks its argument: a callee that hands its argument to another task, a
// leak however precise the analysis of builtins becomes.
const LEAK: string = "function keep(xs: int[]) -> int { let child = spawn { xs.length() }; await child }";

// port: baml_tests/src/compiler2_mir/escape.rs::MASKED @ d9be6853b
const MASKED: string = `
    function total(xs: int[], ys: int[]) -> int { xs[0] + ys[0] }
    function forward(xs: int[], shared: int[][]) -> int {
      let mine = [1];
      shared.push(mine);
      total(xs, [2])
    }
    function leaky(xs: int[]) -> int {
      let child = spawn { xs.length() };
      await child
    }
    function main(outside: int[][]) -> int {
      let xs = [1];
      forward(xs, outside) + leaky([3])
    }
`;

// port: baml_tests/src/compiler2_mir/escape.rs::audit_unrelated_iter_method_can_spawn_with_receiver @ d9be6853b
test "audit unrelated iter method can spawn with receiver" {
    assert_locality(
        `
            interface Launchable {
                function iter(self) -> int throws never;
            }
            implements Launchable for int[] {
                function iter(self) -> int {
                    let child = spawn { self.push(1) };
                    0
                }
            }
            function main() -> int {
                let xs = [1];
                let result = Launchable.iter(xs);
                xs.push(2);
                result
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::reassigned_iterator_parameter_calls_escape @ d9be6853b
test "reassigned iterator parameter calls escape" {
    let source = `
        function consume(it: baml.iter.Iterator<Item = int, Error = never>) -> int {
            let before = it.next();
            let xs = [1];
            it = xs.iter();
            let after = it.next();
            0
        }
    `;
    let (let locals, _) = needs(source, "consume");
    // The incoming iterator may run user code and retain its receiver. Its
    // single body assignment must not make either next call an array step.
    for (let name in ["it", "xs"]) {
        assert.equal(`${name}: ${needs_of(locals, name)}`, `${name}: ${root.mir.NEVER}`);
    }
}

// port: baml_tests/src/compiler2_mir/escape.rs::source_dependency_calls_are_opaque @ d9be6853b
test "source dependency calls are opaque" {
    let t = make_db();
    t.dependency("dep");
    t.file(
        "<builtin>/dep/lib.baml",
        `
            function fresh() -> int[] { [1] }
            function read(xs: int[]) -> int { xs[0] }
        `,
    );
    let file = t.file(
        "test.baml",
        `
            function recurse(xs: int[], n: int) -> int {
                if (n > 0) { recurse(xs, n - 1) } else { dep.read(xs) }
            }
            function main() -> int {
                let made = dep.fresh();
                let passed = [2];
                let recursive = [3];
                dep.read(passed) + recurse(recursive, 1) + made[0] + passed[0] + recursive[0]
            }
        `,
    );
    let actual = classify_file(t, file, "main");
    // Dependency source must not supply escape summaries.
    for (let name in ["made", "passed", "recursive"]) {
        assert.equal(
            actual.some((entry) -> {
                entry.0 == name && !entry.1
            }),
            true,
        );
    }
}

// port: baml_tests/src/compiler2_mir/escape.rs::fresh_array_built_and_read_is_thread_local @ d9be6853b
test "fresh array built and read is thread local" {
    assert_locality(
        `
            function main() -> int {
              let xs = [1, 2];
              xs.push(3);
              let total = 0;
              for (let x in xs) { total += x; }
              total + xs[0] + xs.length()
            }
        `,
        "main",
        [("xs", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::returning_an_object_keeps_it_thread_local @ d9be6853b
test "returning an object keeps it thread local" {
    assert_locality(
        `
            function main() -> int[] {
              let xs = [1];
              xs[0] = 2;
              xs
            }
        `,
        "main",
        [("xs", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::parameters_are_shared @ d9be6853b
test "parameters are shared" {
    assert_locality(
        `
            function main(ys: int[]) -> int {
              let zs = ys;
              zs[0]
            }
        `,
        "main",
        [("ys", false), ("zs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::passing_to_a_leaking_call_shares_every_alias @ d9be6853b
test "passing to a leaking call shares every alias" {
    assert_locality(
        `
            ${LEAK}
            function main() -> int {
              let xs = [1];
              let alias = xs;
              keep(alias)
            }
        `,
        "main",
        [("xs", false), ("alias", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::storing_into_a_shared_object_shares_the_value @ d9be6853b
test "storing into a shared object shares the value" {
    assert_locality(
        `
            class Box {
              items: int[]
            }
            function main(b: Box) -> int {
              let xs = [1];
              b.items = xs;
              xs[0]
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::storing_into_a_fresh_object_keeps_both_thread_local @ d9be6853b
test "storing into a fresh object keeps both thread local" {
    assert_locality(
        `
            class Box {
              items: int[]
            }
            function main() -> int {
              let xs = [1];
              let b = Box { items: xs };
              b.items[0] + xs[0]
            }
        `,
        "main",
        [("xs", true), ("b", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::leaking_a_loaded_element_shares_what_was_stored @ d9be6853b
test "leaking a loaded element shares what was stored" {
    assert_locality(
        `
            ${LEAK}
            function main() -> int {
              let inner = [1];
              let outer = [inner];
              let again = outer[0];
              keep(again)
            }
        `,
        "main",
        [("inner", false), ("again", false), ("outer", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::pushing_onto_a_shared_array_shares_the_item @ d9be6853b
test "pushing onto a shared array shares the item" {
    assert_locality(
        `
            function main(out: int[][]) -> int {
              let xs = [1];
              out.push(xs);
              xs[0]
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::method_receivers_follow_the_method_summary @ d9be6853b
test "method receivers follow the method summary" {
    assert_locality(
        `
            class Point {
              x: int
              function get(self) -> int { self.x }
            }
            function main() -> int {
              let p = Point { x: 1 };
              let q = Point { x: 2 };
              q.x = 3;
              p.get() + q.x
            }
        `,
        "main",
        [("p", true), ("q", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::closures_share_what_they_capture @ d9be6853b
test "closures share what they capture" {
    assert_locality(
        `
            function main() -> int {
              let xs = [1];
              let f = () -> int { xs[0] };
              f()
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::spawned_work_shares_its_plan @ d9be6853b
test "spawned work shares its plan" {
    assert_locality(
        `
            function first(xs: int[]) -> int { xs[0] }
            function main() -> int {
              let xs = [1];
              let ys = [2];
              let f = spawn { first(xs) };
              ys[0] + await f
            }
        `,
        "main",
        [("xs", false), ("ys", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::thrown_values_are_shared @ d9be6853b
test "thrown values are shared" {
    assert_locality(
        `
            function main() -> int {
              let xs = [1];
              if (xs[0] > 0) { throw xs; }
              0
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::string_keyed_maps_stay_thread_local @ d9be6853b
test "string keyed maps stay thread local" {
    assert_locality(
        `
            function main() -> int {
              let m = {"a": 1};
              m["b"] = 2;
              if (m.has("a")) { m["a"] } else { 0 }
            }
        `,
        "main",
        [("m", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::map_values_that_leak_share_the_map_contents @ d9be6853b
test "map values that leak share the map contents" {
    assert_locality(
        `
            ${LEAK}
            function main() -> int {
              let xs = [1];
              let m = {"a": xs};
              keep(m["a"])
            }
        `,
        "main",
        [("xs", false), ("m", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::an_iterator_that_leaks_shares_its_array @ d9be6853b
test "an iterator that leaks shares its array" {
    assert_locality(
        `
            function drain<T>(it: T) -> int { let child = spawn { [it].length() }; await child }
            function main() -> int {
              let xs = [1, 2];
              drain(xs.iter())
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_callee_that_only_reads_keeps_arguments_thread_local @ d9be6853b
test "a callee that only reads keeps arguments thread local" {
    assert_locality(
        `
            function first(xs: int[]) -> int { xs[0] + xs.length() }
            function main() -> int {
              let xs = [1];
              first(xs) + xs[0]
            }
        `,
        "main",
        [("xs", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_fresh_return_value_is_thread_local_in_the_caller @ d9be6853b
test "a fresh return value is thread local in the caller" {
    assert_locality(
        `
            function make(n: int) -> int[] { [n, n + 1] }
            function main() -> int {
              let xs = make(1);
              xs[0] = 3;
              xs[1]
            }
        `,
        "main",
        [("xs", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_returned_argument_aliases_it_in_the_caller @ d9be6853b
test "a returned argument aliases it in the caller" {
    assert_locality(
        `
            ${LEAK}
            function same(xs: int[]) -> int[] { xs }
            function main() -> int {
              let xs = [1];
              let ys = same(xs);
              keep(ys)
            }
        `,
        "main",
        [("xs", false), ("ys", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_callee_that_stores_one_argument_in_another_links_them @ d9be6853b
test "a callee that stores one argument in another links them" {
    assert_locality(
        `
            function put(out: int[][], xs: int[]) -> int { out.push(xs) }
            function main(shared: int[][]) -> int {
              let xs = [1];
              let fresh: int[][] = [];
              let ys = [2];
              put(shared, xs);
              put(fresh, ys);
              xs[0] + ys[0]
            }
        `,
        "main",
        [("xs", false), ("fresh", true), ("ys", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_recursive_callee_that_only_reads_keeps_arguments_thread_local @ d9be6853b
test "a recursive callee that only reads keeps arguments thread local" {
    assert_locality(
        `
            function walk(xs: int[], n: int) -> int {
              if (n == 0) { xs[0] } else { walk(xs, n - 1) }
            }
            function main() -> int {
              let xs = [1];
              walk(xs, 3)
            }
        `,
        "main",
        [("xs", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_recursive_callee_that_spawns_at_its_base_case_shares_arguments @ d9be6853b
test "a recursive callee that spawns at its base case shares arguments" {
    assert_locality(
        `
            function walk(xs: int[], n: int) -> int {
              if (n == 0) {
                let child = spawn { xs.length() };
                await child
              } else {
                walk(xs, n - 1)
              }
            }
            function main() -> int {
              let xs = [1];
              walk(xs, 3)
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::mutually_recursive_callees_share_what_either_leaks @ d9be6853b
test "mutually recursive callees share what either leaks" {
    assert_locality(
        `
            function even(xs: int[], n: int) -> int {
              if (n == 0) { xs[0] } else { odd(xs, n - 1) }
            }
            function odd(xs: int[], n: int) -> int {
              if (n == 0) {
                let child = spawn { xs.length() };
                await child
              } else {
                even(xs, n - 1)
              }
            }
            function main() -> int {
              let xs = [1];
              let ys = [2];
              even(xs, 3) + ys[0]
            }
        `,
        "main",
        [("xs", false), ("ys", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::leaks_compose_through_calls @ d9be6853b
test "leaks compose through calls" {
    assert_locality(
        `
            ${LEAK}
            function forward(xs: int[]) -> int { keep(xs) }
            function main() -> int {
              let xs = [1];
              forward(xs)
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::immutable_values_do_not_share_their_neighbours @ d9be6853b
test "immutable values do not share their neighbours" {
    assert_locality(
        `
            ${LEAK}
            function shout(s: string) -> int { [s].reverse().length() }
            class Named {
              name: string
              items: int[]
            }
            function main() -> int {
              let n = Named { name: "a", items: [1] };
              let name = n.name;
              shout(name) + shout(n.name) + n.items[0]
            }
        `,
        "main",
        [("n", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::builtin_calls_on_a_field_receiver_are_seen_through @ d9be6853b
test "builtin calls on a field receiver are seen through" {
    assert_locality(
        `
            class Queue {
              items: int[]
            }
            function main() -> int {
              let q = Queue { items: [] };
              q.items.push(1);
              q.items.length() + q.items[0]
            }
        `,
        "main",
        [("q", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::map_keys_and_values_copy_the_entries @ d9be6853b
test "map keys and values copy the entries" {
    assert_locality(
        `
            ${LEAK}
            function main() -> int {
              let xs = [1];
              let m = {"a": xs};
              let ks = m.keys();
              let vs = m.values();
              keep(vs[0]) + ks.length()
            }
        `,
        "main",
        [("xs", false), ("m", true), ("ks", true), ("vs", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::class_keyed_maps_stay_opaque @ d9be6853b
test "class keyed maps stay opaque" {
    assert_locality(
        `
            class Key {
              k: int
            }
            function main(key: Key) -> int {
              let m: map<Key, int[]> = {};
              let xs = [1];
              m[key] = xs;
              xs[0]
            }
        `,
        "main",
        [("xs", false), ("m", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::comparing_with_null_runs_no_user_code @ d9be6853b
test "comparing with null runs no user code" {
    assert_locality(
        `
            class Node {
              next: Node?
              value: int
            }
            function main() -> int {
              let n = Node { next: null, value: 1 };
              let m = Node { next: null, value: 2 };
              let o = Node { next: null, value: 3 };
              if (o.next == null && n != m) { n.value + o.value } else { 0 }
            }
        `,
        "main",
        [("n", false), ("m", false), ("o", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::fresh_results_of_declared_builtins_are_thread_local @ d9be6853b
test "fresh results of declared builtins are thread local" {
    assert_locality(
        `
            function main(s: string) -> int {
              let parts = s.split(",");
              let cps = s.to_code_points();
              let xs = [1, 2];
              let ys = xs.reverse();
              parts.length() + cps[0] + ys[0] + xs[0]
            }
        `,
        "main",
        [("parts", true), ("cps", true), ("xs", true), ("ys", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::inserting_into_a_shared_array_shares_the_item @ d9be6853b
test "inserting into a shared array shares the item" {
    assert_locality(
        `
            function main(shared: int[][]) -> int {
              let xs = [1];
              let ys = [2];
              let zs = [3];
              shared.insert(xs, 0);
              shared.unshift(ys);
              let local: int[][] = [];
              local.insert(zs, 0);
              xs[0] + ys[0] + zs[0] + local.length()
            }
        `,
        "main",
        [("xs", false), ("ys", false), ("zs", true), ("local", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_parameter_is_thread_local_given_its_own_bit @ d9be6853b
test "a parameter is thread local given its own bit" {
    let (let locals, _) = needs(MASKED, "forward");
    assert.equal(needs_of(locals, "xs"), 1n);
    assert.equal(needs_of(locals, "shared"), 2n);
    // Stored into `shared`'s contents: as thread-local as `shared` is.
    assert.equal(needs_of(locals, "mine"), 2n)
}

// port: baml_tests/src/compiler2_mir/escape.rs::a_parameter_the_body_leaks_is_never_thread_local @ d9be6853b
test "a parameter the body leaks is never thread local" {
    let (let locals, _) = needs(MASKED, "leaky");
    assert.equal(needs_of(locals, "xs"), root.mir.NEVER)
}

// port: baml_tests/src/compiler2_mir/escape.rs::callers_pass_what_they_prove_about_each_argument @ d9be6853b
test "callers pass what they prove about each argument" {
    // `total(xs, [2])`: `xs` given the caller's first bit, a fresh array
    // always.
    let (_, let forward_calls) = needs(MASKED, "forward");
    assert.equal(forward_calls, [[1n, 0n]]);
    // `forward(xs, outside)`: a fresh array always, a parameter given its
    // bit. `leaky([3])` passes no mask at all: the callee leaks its
    // argument.
    let (_, let main_calls) = needs(MASKED, "main");
    assert.equal(main_calls, [[0n, 1n]])
}

// port: baml_tests/src/compiler2_mir/escape.rs::callbacks_share_elements_without_sharing_the_receiver @ d9be6853b
test "callbacks share elements without sharing the receiver" {
    assert_locality(
        `
            class Item { value: int }
            function main() -> int {
              let item = Item { value: 1 };
              let items = [item];
              let mapped = items.map((x: Item) -> Item { x });
              mapped[0].value + items.length()
            }
        `,
        "main",
        [("item", false), ("items", true), ("mapped", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::string_conversion_overrides_share_elements_without_sharing_the_receiver @ d9be6853b
test "string conversion overrides share elements without sharing the receiver" {
    assert_locality(
        `
            class Item { value: int }
            function main() -> int {
              let item = Item { value: 1 };
              let items = [item];
              let text = items.join(",");
              items.length() + text.length()
            }
        `,
        "main",
        [("item", false), ("items", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::observed_array_iterator_keeps_its_object @ d9be6853b
// The `array_walks` half; the bytecode half needs emit.
test "observed array iterator keeps its object" {
    let source = `
        function observe(it: baml.iter.Iterator<Item = int, Error = never>) -> void {
          it.next();
        }
        function observed(xs: int[]) -> int {
          let it = xs.iter();
          observe(it);
          let total = 0;
          for (let x in it) { total += x; }
          total
        }
    `;
    let t = make_db();
    let file = t.file("test.baml", source);
    let (let body, let arity) = lower_named(t, file, "observed", root.mir.OptLevel.Two);
    assert.equal(
        root.mir.array_walks(t.db, body, arity).every((walk) -> {
            !walk
        }),
        true,
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::awaited_objects_are_shared @ d9be6853b
test "awaited objects are shared" {
    assert_locality(
        `
            function main() -> int {
                let child = spawn { [42] };
                let xs = await child;
                xs[0]
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::global_objects_are_shared @ d9be6853b
test "global objects are shared" {
    assert_locality(
        `
            const SHARED = [42];
            function main() -> int {
                let xs = SHARED;
                xs[0]
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::sysop_results_are_shared @ d9be6853b
test "sysop results are shared" {
    assert_locality(
        `
            function main() -> bool {
                let glob = baml.glob.new("*");
                glob.matches("file")
            }
        `,
        "main",
        [("glob", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::an_uncaptured_alias_of_a_captured_value_is_shared @ d9be6853b
test "an uncaptured alias of a captured value is shared" {
    assert_locality(
        `
            function main() -> int {
                let original = [1];
                let captured = original;
                let read = () -> int { captured[0] };
                original[0] + read()
            }
        `,
        "main",
        [("original", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::an_explicit_spawn_plan_is_shared @ d9be6853b
test "an explicit spawn plan is shared" {
    assert_locality(
        `
            function main() -> int {
                let plan = baml.spawn.Plan<int, never> {
                    body: () -> int throws never { 1 },
                    name: null,
                    semaphores: [],
                    cancel_tokens: [],
                    root: false,
                };
                let child = baml.spawn.__spawn(plan);
                await child
            }
        `,
        "main",
        [("plan", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::sysop_arguments_are_shared @ d9be6853b
test "sysop arguments are shared" {
    // A sys-op receives its object arguments as heap handles.
    assert_locality(
        `
            function main() -> int {
                let options = baml.glob.ScanOptions {
                    cwd: null,
                    dot: null,
                    absolute: null,
                    follow_symlinks: null,
                    throw_error_on_broken_symlink: null,
                    only_files: null,
                };
                let fresh = baml.glob.ScanOptions {
                    cwd: null,
                    dot: null,
                    absolute: null,
                    follow_symlinks: null,
                    throw_error_on_broken_symlink: null,
                    only_files: null,
                };
                options.dot = true;
                fresh.dot = true;
                let paths = baml.glob.new("*").scan(options);
                paths.length()
            }
        `,
        "main",
        [("options", false), ("fresh", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::fields_of_a_finalized_instance_are_shared @ d9be6853b
test "fields of a finalized instance are shared" {
    // The collector runs `cleanup` in a VM of its own once the instance is
    // garbage, while `main` may still hold the array.
    assert_locality(
        `
            class Resource {
                log: int[],
                function cleanup(self) -> void throws never { self.log.push(0); }
            }
            class Plain {
                log: int[],
            }
            function main() -> int {
                let held = [1];
                let resource = Resource { log: held };
                let kept = [2];
                let plain = Plain { log: kept };
                resource.log.push(3);
                plain.log.push(4);
                held[0] + kept[0]
            }
        `,
        "main",
        [("held", false), ("kept", true), ("resource", true), ("plain", true)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::fields_of_a_finalized_instance_built_in_a_callee_are_shared @ d9be6853b
test "fields of a finalized instance built in a callee are shared" {
    assert_locality(
        `
            class Resource {
                log: int[],
                function cleanup(self) -> void throws never { self.log.push(0); }
            }
            function abandon(log: int[]) -> void throws never {
                let resource = Resource { log };
                resource.log.push(-1);
            }
            function main() -> int {
                let log: int[] = [];
                abandon(log);
                log.push(1);
                log[0]
            }
        `,
        "main",
        [("log", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::dependency_classes_may_finalize @ d9be6853b
test "dependency classes may finalize" {
    // Whether a dependency's class has a finalizer must not depend on
    // whether its source is mounted: assume it may.
    let t = make_db();
    t.dependency("dep");
    t.file(
        "<builtin>/dep/lib.baml",
        `
            class Box {
                items: int[],
            }
        `,
    );
    let file = t.file(
        "test.baml",
        `
            function main() -> int {
                let items = [1];
                let boxed = dep.Box { items };
                items.push(2);
                boxed.items[0]
            }
        `,
    );
    let actual = classify_file(t, file, "main");
    // A dependency class may have a finalizer.
    assert.equal(
        actual.some((entry) -> {
            entry.0 == "items" && !entry.1
        }),
        true,
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::review_late_publication_through_returned_alias @ d9be6853b
test "review late publication through returned alias" {
    assert_locality(
        `
            function identity(xs: int[]) -> int[] { xs }
            function publish(xs: int[]) -> void { let child = spawn { xs.push(9) }; }
            function main() -> int {
                let xs = [1];
                xs.push(2);
                let alias = identity(xs);
                publish(alias);
                xs[0]
            }
        `,
        "main",
        [("xs", false), ("alias", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::review_map_callback_returns_shared_array @ d9be6853b
test "review map callback returns shared array" {
    assert_locality(
        `
            function main(shared: int[]) -> int {
                let mapped = [1].map((n: int) -> int[] { shared });
                let item = mapped[0];
                item.push(2);
                item[0]
            }
        `,
        "main",
        [("mapped", true), ("item", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::review_defer_publishes_array_after_local_access @ d9be6853b
test "review defer publishes array after local access" {
    assert_locality(
        `
            function publish(xs: int[]) -> void { let child = spawn { xs.push(9) }; }
            function main() -> int {
                let xs = [1];
                defer { publish(xs); }
                xs.push(2);
                xs[0]
            }
        `,
        "main",
        [("xs", false)],
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::review_nested_container_mask_requires_shared_contents @ d9be6853b
test "review nested container mask requires shared contents" {
    let (let locals, let calls) = needs(
        `
            function read(nested: int[][]) -> int { nested[0][0] }
            function main(shared: int[]) -> int {
                let nested = [shared];
                read(nested)
            }
        `,
        "main",
    );
    assert.equal(needs_of(locals, "nested"), 0n);
    assert.equal(
        calls.some((args) -> {
            args == [1n]
        }),
        true,
    )
}

// port: baml_tests/src/compiler2_mir/escape.rs::review_parameters_beyond_locality_mask_are_shared @ d9be6853b
test "review parameters beyond locality mask are shared" {
    let params: string[] = [];
    for (let i = 0; i < 65; i += 1) {
        params.push(`p${i}: int[]`);
    }
    let source = `function main(${params.join(", ")}) -> int { p64[0] }`;
    let (let locals, _) = needs(source, "main");
    assert.equal(needs_of(locals, "p63"), 1n << 63n);
    assert.equal(needs_of(locals, "p64"), root.mir.NEVER)
}

// port: baml_tests/src/compiler2_mir/escape.rs::review_summary_invalidates_when_callee_starts_spawning @ d9be6853b
// Restructured: the edited source is classified on a fresh Db (no salsa
// `set_text` here).
test "review summary invalidates when callee starts spawning" {
    let source = `
        function helper(xs: int[]) -> int { xs.length() }
        function main() -> int { let xs = [1]; helper(xs); xs[0] }
    `;
    let before = make_db();
    let before_file = before.file("test.baml", source);
    for (let opt in [root.mir.OptLevel.One, root.mir.OptLevel.Two]) {
        let locals = classify_file_at_opt(before, before_file, "main", opt);
        assert.equal(
            locals.some((entry) -> {
                entry.0 == "xs" && entry.1
            }),
            true,
        );
    }
    let after = make_db();
    let after_file = after.file(
        "test.baml",
        source.replace("xs.length()", "let child = spawn { xs.push(9) }; xs.length()"),
    );
    for (let opt in [root.mir.OptLevel.One, root.mir.OptLevel.Two]) {
        let locals = classify_file_at_opt(after, after_file, "main", opt);
        assert.equal(
            locals.some((entry) -> {
                entry.0 == "xs" && !entry.1
            }),
            true,
        );
    }
}
