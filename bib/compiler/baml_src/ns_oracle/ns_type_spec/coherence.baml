// port: baml_tests/src/type_spec/coherence.rs @ d9be6853b
//
// Differential coherence tests: hir_ty's `package_coherence_violations` /
// `package_orphan_violations` (ns_hir_ty/coherence.baml) against TIR's
// `package_coherence_diagnostics` (ns_hir_ty/ns_interfaces/coherence.baml)
// over the same sources. Violations are compared as sets of
// `(primary range, secondary range, indeterminate)`: the two engines must
// agree pair for pair, and each case pins the expected (definite,
// indeterminate) counts so the agreement is never vacuous.
//
// The TIR side is not a retired engine: `package_coherence_diagnostics` is
// the live per-package check behind E0132 (check_types.baml calls it), and
// it is ported, so `tir_pairs` is a direct port.
//
// Restructured:
// - `hir_ty_pairs` and `tir_pairs` read one Db (a stdlib Db with
//   `test.baml` in a new workspace root, `coherence_db`) instead of a fresh
//   database each; both are pure queries over the same package.
// - A violation pair is a tuple `(TextRange, TextRange, bool)`; Rust's
//   `sort_by_key((p.start, p.end, s.start, s.end))` is `sort_by` on those
//   four offsets (stable, as Rust's).
// - `check_coherence`'s `assert!(agree, ..)` is a panic with the same
//   message (both pair lists); its `assert_eq!` on the counts is
//   `assert.equal` on the count tuple. `check_orphans`'s is `assert.equal`.
// - Backtick sources drop Rust's leading and trailing newline (every line
//   starts at column 0, so dedent strips nothing else); ranges are compared
//   between the two engines on the same text.

// One violation as source ranges: (primary, secondary, indeterminate).
type CoherencePair = (root.syntax.TextRange, root.syntax.TextRange, bool);

// A stdlib Db holding `source` as `test.baml` in a new workspace root, and
// that file's package (Rust's `user_package`: `file_package(db, file).root`).
function coherence_db(source: string) -> (root.hir.Db, int) throws never {
    let db = root.stdlib_db();
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    let file = root.db.add_file(db, workspace, "test.baml", source);
    (db, root.hir.file_package(db, file).root_id)
}

// The sort key order `(p.start, p.end, s.start, s.end)`.
function sort_coherence_pairs(pairs: CoherencePair[]) -> CoherencePair[] throws never {
    pairs.sort_by((a, b) -> {
        let keys = [
            a.0.start.cmp(b.0.start),
            a.0.end.cmp(b.0.end),
            a.1.start.cmp(b.1.start),
            a.1.end.cmp(b.1.end),
        ];
        keys.find((k) -> {
            k != baml.ops.Ordering.Equal
        })
            ?? baml.ops.Ordering.Equal
    })
}

// port: baml_tests/src/type_spec/coherence.rs::hir_ty_pairs @ d9be6853b
// hir_ty's violations, each impl loc mapped to its whole block span.
function hir_ty_pairs(db: root.hir.Db, pkg: int) -> CoherencePair[] throws never {
    let span_of = (loc: int) -> root.syntax.TextRange {
        root.hir.impl_block_source_map(db, loc).span
    };
    sort_coherence_pairs(
        root.hir_ty.package_coherence_violations(db, pkg).map((violation) -> {
            (span_of(violation.primary), span_of(violation.secondary), violation.indeterminate)
        }),
    )
}

// port: baml_tests/src/type_spec/coherence.rs::tir_pairs @ d9be6853b
function tir_pairs(db: root.hir.Db, pkg: int) -> CoherencePair[] throws never {
    sort_coherence_pairs(
        root.hir_ty.interfaces.package_coherence_diagnostics(db, pkg).map((violation) -> {
            (violation.primary.range, violation.secondary.range, violation.indeterminate)
        }),
    )
}

// `(start..end, start..end, indeterminate)` per pair, for failure messages.
function render_coherence_pairs(pairs: CoherencePair[]) -> string throws never {
    let rendered = pairs.map((p) -> {
        `(${p.0.start}..${p.0.end}, ${p.1.start}..${p.1.end}, ${p.2})`
    });
    `[${rendered.join(", ")}]`
}

// port: baml_tests/src/type_spec/coherence.rs::check_coherence @ d9be6853b
// Both engines over `source`: they must agree AND match the expected
// (definite, indeterminate) violation counts. Spans compare by
// CONTAINMENT: hir_ty maps a violation to its whole impl-block span, while
// TIR anchors some on a sub-span of the block.
function check_coherence(source: string, definite: int, indeterminate: int) -> void throws never {
    let (let db, let pkg) = coherence_db(source);
    let hir = hir_ty_pairs(db, pkg);
    let tir = tir_pairs(db, pkg);
    let contains = (outer: root.syntax.TextRange, inner: root.syntax.TextRange) -> bool {
        outer.start <= inner.start && inner.end <= outer.end
    };
    let agree = hir.length() == tir.length();
    for (let i = 0; agree && i < hir.length(); i += 1) {
        let h = hir[i];
        let t = tir[i];
        agree = contains(h.0, t.0) && contains(h.1, t.1) && h.2 == t.2;
    }
    if (!agree) {
        baml.sys.panic(
            `engines disagree on coherence violations\n  hir_ty: ${render_coherence_pairs(hir)}\n  tir: ${render_coherence_pairs(tir)}`,
        );
    }
    let got_definite = hir
        .filter((p) -> {
            !p.2
        })
        .length();
    let got_indeterminate = hir
        .filter((p) -> {
            p.2
        })
        .length();
    assert.equal((got_definite, got_indeterminate), (definite, indeterminate));
}

// port: baml_tests/src/type_spec/coherence.rs::check_orphans @ d9be6853b
// hir_ty orphan outcomes: the uncovered param (or null) per violation, in
// source order.
function check_orphans(source: string, expected: string?[]) -> void throws never {
    let (let db, let pkg) = coherence_db(source);
    let got = root.hir_ty.package_orphan_violations(db, pkg).map((violation) -> {
        violation.uncovered_param
    });
    assert.equal(got, expected);
}

// port: baml_tests/src/type_spec/coherence.rs::duplicate_in_body_impls_overlap @ d9be6853b
// A duplicate block is a degenerate overlap (rustc's
// conflicting-implementations error for exact duplicates).
test "duplicate in body impls overlap" {
    check_coherence(
        `
            interface Marker {}

            class C {
                x int
                implements Marker {}
                implements Marker {}
            }
        `,
        1,
        0,
    )
}

// port: baml_tests/src/type_spec/coherence.rs::complementary_blankets_share_common_instance @ d9be6853b
// `Pair<T, int>` vs `Pair<string, U>`: common instance `Pair<string, int>`,
// found only by SYMMETRIC unification (either side may bind).
test "complementary blankets share common instance" {
    check_coherence(
        `
            interface Marker {}

            class Pair<A, B> {
                a A
                b B
            }

            implement<T> Marker for Pair<T, int> {}
            implement<U> Marker for Pair<string, U> {}
        `,
        1,
        0,
    )
}

// port: baml_tests/src/type_spec/coherence.rs::distinct_subjects_are_disjoint @ d9be6853b
test "distinct subjects are disjoint" {
    check_coherence(
        `
            interface Marker {}

            implement Marker for int {}
            implement Marker for string {}
        `,
        0,
        0,
    )
}

// port: baml_tests/src/type_spec/coherence.rs::alias_obscured_duplicate_overlaps @ d9be6853b
// `type AI = int`: the alias-expanded heads collide; missing the expansion
// would admit two impls for one concrete type (fails open).
test "alias obscured duplicate overlaps" {
    check_coherence(
        `
            interface Marker {}

            type AI = int

            implement Marker for int {}
            implement Marker for AI {}
        `,
        1,
        0,
    )
}

// port: baml_tests/src/type_spec/coherence.rs::bound_refutes_common_instance @ d9be6853b
// `implement<T extends Other> Marker for Box<T>` vs
// `implement Marker for Box<C>`: the unifier pins `T := C`, and `C`
// provably does not implement `Other`, so the pair is disjoint.
test "bound refutes common instance" {
    check_coherence(
        `
            interface Marker {}
            interface Other {}

            class Box<T> {
                value T
            }

            class C {
                x int
            }

            implement<T extends Other> Marker for Box<T> {}
            implement Marker for Box<C> {}
        `,
        0,
        0,
    )
}

// port: baml_tests/src/type_spec/coherence.rs::satisfied_bound_keeps_overlap @ d9be6853b
// Same shape, but `C` DOES implement `Other`: the bound holds at the common
// instance, so the overlap is real.
test "satisfied bound keeps overlap" {
    check_coherence(
        `
            interface Marker {}
            interface Other {}

            class Box<T> {
                value T
            }

            class C {
                x int
                implements Other {}
            }

            implement<T extends Other> Marker for Box<T> {}
            implement Marker for Box<C> {}
        `,
        1,
        0,
    )
}

// port: baml_tests/src/type_spec/coherence.rs::orphan_local_type_covers_foreign_interface @ d9be6853b
// A local class implementing a stdlib interface: covered, no violation.
test "orphan local type covers foreign interface" {
    check_orphans(
        `
            class C {
                x int
                implements baml.ops.Equals {
                    function eq(self, other: C) -> bool throws never {
                        true
                    }
                }
            }
        `,
        [],
    )
}

// port: baml_tests/src/type_spec/coherence.rs::orphan_foreign_for_foreign_is_violation @ d9be6853b
// A foreign interface for a foreign type: no local type anywhere in the
// impl's inputs (E0139).
test "orphan foreign for foreign is violation" {
    check_orphans(
        `
            implement baml.ops.Equals for baml.iter.Done {}
        `,
        [null],
    )
}

// port: baml_tests/src/type_spec/coherence.rs::orphan_uncovered_param_is_violation @ d9be6853b
// `implement<T> baml.ops.Equals for T`: the bare param precedes any local
// type (RFC-2451's covered rule).
test "orphan uncovered param is violation" {
    check_orphans(
        `
            implement<T> baml.ops.Equals for T {}
        `,
        ["T"],
    )
}
