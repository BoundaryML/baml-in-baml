// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs @ d9be6853b
//
// Per-package interface coherence: no two `implements` blocks of the same
// interface may overlap. Overlap is decided by the shared equality
// unification engine (`root.types.unify_into`): the two impls' generic
// params are renamed to disjoint unification variables, the for-types and
// interface args must unify position-wise, and a bound a pinned param
// provably violates makes the pair disjoint.
//
// Restructured (BAML forces it):
// - `PreparedImpl`'s `OnceCell<bool>` is a nullable field set on first use.
// - `overlap_violation`'s `Option<bool>` is `bool?`.
// - A side `prefix` (`char`) is a one-letter string.
// - The `EnumVariants` closure reads `root.hir_ty.uncached_enum_variants`
//   (Rust's `enum_variant_names`, a one-line forward).

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::overlap_violation @ d9be6853b
// An overlap result as a reportable violation: null is disjoint (no
// diagnostic); otherwise whether the violation is the conservative "couldn't
// prove disjoint" case.
function overlap_violation(overlap: root.types.Overlap) -> bool? throws never {
    match (overlap) {
        root.types.Overlap.No => null,
        root.types.Overlap.Yes => false,
        root.types.Overlap.Unknown => true,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::CoherenceViolation @ d9be6853b
// Two implementations of the same interface that overlap, or that could not
// be proven disjoint.
class CoherenceViolation {
    // The offending impl, always owned by the package being checked.
    primary: root.base.Span,
    // The impl it overlaps with; may live in a dependency package.
    secondary: root.base.Span,
    // Overlap could be neither proven nor disproven (conservatively
    // rejected) rather than a definite overlap.
    indeterminate: bool,
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::package_coherence_diagnostics @ d9be6853b
// Overlapping implementations of the same interface across `pkg_id` and its
// dependency closure. Only pairs with at least one impl owned by `pkg_id`
// are reported; dependency-internal conflicts belong to the dependency's
// own check.
function package_coherence_diagnostics(
    db: root.hir.Db,
    pkg_id: int,
) -> CoherenceViolation[] throws never {
    db.ty_memo.package_coherence_diagnostics.get(db.cycles, pkg_id, () -> {
        let own = package_impls_with_spans(db, pkg_id);
        // Every reported pair contains an implementation owned by this
        // package.
        if (own.length() == 0) {
            return [];
        }
        // Sort by source position `(file, start, end)` so the overlap
        // attribution tracks a stable textual order.
        own.sort_by((a, b) -> {
            let by_file = a.span.file_id.cmp(b.span.file_id);
            if (by_file != baml.ops.Ordering.Equal) {
                return by_file;
            }
            let by_start = a.span.range.start.cmp(b.span.range.start);
            if (by_start != baml.ops.Ordering.Equal) {
                return by_start;
            }
            a.span.range.end.cmp(b.span.range.end)
        });
        let deps = root.hir.package_dependency_closure(db, pkg_id);

        // Type aliases (own package plus dependency exports), pre-normalized
        // so alias-referencing subjects compare by the same union laws as
        // their spelled-out forms.
        let aliases = normalized_alias_map(db, pkg_id);

        let dep_impls = deps.flat_map((dep) -> {
            package_impls_with_spans(db, dep)
        });

        let violations: CoherenceViolation[] = [];
        for (let i = 0; i < own.length(); i += 1) {
            let own_impl = own[i];
            // own x own: each unordered pair once; the later impl carries
            // the error.
            for (let other in own.slice(i + 1, own.length())) {
                let indeterminate = overlap_violation(impls_conflict(db, pkg_id, own_impl, other, aliases));
                if (indeterminate != null) {
                    violations.push(
                        CoherenceViolation {
                            primary: other.span,
                            secondary: own_impl.span,
                            indeterminate: indeterminate,
                        },
                    );
                }
            }
            // own x dependency: the owning package's impl carries the error.
            for (let dep in dep_impls) {
                let indeterminate = overlap_violation(impls_conflict(db, pkg_id, own_impl, dep, aliases));
                if (indeterminate != null) {
                    violations.push(
                        CoherenceViolation {
                            primary: own_impl.span,
                            secondary: dep.span,
                            indeterminate: indeterminate,
                        },
                    );
                }
            }
        }
        violations
    })
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::package_impls_with_spans @ d9be6853b
// The impls of `pkg_id` the overlap check compares, each prepared once.
function package_impls_with_spans(db: root.hir.Db, pkg_id: int) -> PreparedImpl[] throws never {
    package_impl_locs(db, pkg_id).filter_map((loc) -> {
        let data = match (impl_data(db, loc)) {
            let d: ImplData => d,
            _ => {
                return null;
            },
        };
        PreparedImpl {
            data: data,
            span: impl_data_source_map(db, loc).impl_span,
            interface_: interface_loc_qtn(db, data.interface_),
            loc: loc,
            valid_subject_cache: null,
        }
    })
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::PreparedImpl @ d9be6853b
// An impl prepared for the pairwise overlap loops: the pair-invariant facts
// are computed (or lazily memoized) once per impl.
class PreparedImpl {
    data: ImplData,
    span: root.base.Span,
    // The implemented interface, or null when it did not resolve (such an
    // impl conflicts with nothing).
    interface_: root.types.DeclName?,
    // The block itself, so the subject gate reads the header's one validity
    // decision.
    loc: int,
    // Memoized `valid_subject` (Rust's `OnceCell`); null until first asked.
    // Renamed: a method has the Rust field's name.
    valid_subject_cache: bool?,

    // port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::PreparedImpl::valid_subject @ d9be6853b
    // Whether this impl's for-target is a valid implementor. An invalid one
    // (rejected by the E0138 gate) contributes no overlap, so no spurious
    // E0132 stacks on that rejection; the gate reads the header's one
    // validity decision (`impl_facts`) so the two never disagree.
    function valid_subject(self, db: root.hir.Db) -> bool throws never {
        let cached = self.valid_subject_cache;
        if (cached != null) {
            return cached;
        }
        let valid = root.hir_ty.impl_facts(db, self.loc) is root.hir_ty.ImplHeaderResolutionResolved;
        self.valid_subject_cache = valid;
        valid
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::impls_conflict @ d9be6853b
// Whether two impls of the same interface conflict (overlap with no
// specialization to rescue them). Distinct interfaces never conflict.
// Same-class in-body duplicates are not excluded: a duplicate is a
// degenerate overlap (E0132).
function impls_conflict(
    db: root.hir.Db,
    pkg_id: int,
    a: PreparedImpl,
    b: PreparedImpl,
    aliases: map<root.types.DeclName, root.types.Ty>,
) -> root.types.Overlap throws never {
    let a_qtn = a.interface_;
    let b_qtn = b.interface_;
    if (a_qtn == null || b_qtn == null || a_qtn != b_qtn) {
        return root.types.Overlap.No;
    }
    // The E0138-mirror gate.
    if (!a.valid_subject(db) || !b.valid_subject(db)) {
        return root.types.Overlap.No;
    }
    impls_overlap(db, pkg_id, a.data, b.data, aliases)
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::impls_overlap @ d9be6853b
// Conservative symmetric overlap test: two impls overlap iff their subjects
// (for-type plus interface args) have a common instance, decided by
// first-order unification with both impls' generic params as fresh
// variables. A bound a pinned ground witness provably violates makes the
// pair disjoint.
function impls_overlap(
    db: root.hir.Db,
    pkg_id: int,
    a: ImplData,
    b: ImplData,
    aliases: map<root.types.DeclName, root.types.Ty>,
) -> root.types.Overlap throws never {
    let enum_variants = (qtn: root.types.DeclName) -> string[]? {
        root.hir_ty.uncached_enum_variants(db, qtn)
    };
    let (let a_for, let a_args) = renamed_subject(a, "a", enum_variants);
    let (let b_for, let b_args) = renamed_subject(b, "b", enum_variants);
    if (a_args.length() != b_args.length()) {
        return root.types.Overlap.No;
    }
    let vars: root.types.ParamTy[] = [];
    for (let i = 0; i < a.generic_params.length(); i += 1) {
        vars.push(renamed_var("a", i));
    }
    for (let i = 0; i < b.generic_params.length(); i += 1) {
        vars.push(renamed_var("b", i));
    }

    let bindings: root.types.TypeBindings = {};
    let alias_ctx = root.types.AliasEquivCtx { aliases: aliases, lang: root.hir.lang_roots(db) };
    // Unify the for-type and each interface arg. A provably-disjoint part
    // short-circuits the pair to disjoint; an undecidable part downgrades a
    // would-be overlap to `Unknown`.
    let result = root.types.unify_into(a_for, b_for, vars, alias_ctx, bindings);
    if (result == root.types.Overlap.No) {
        return root.types.Overlap.No;
    }
    for (let i = 0; i < a_args.length(); i += 1) {
        match (root.types.unify_into(a_args[i], b_args[i], vars, alias_ctx, bindings)) {
            root.types.Overlap.No => {
                return root.types.Overlap.No;
            },
            root.types.Overlap.Unknown => {
                result = root.types.Overlap.Unknown;
            },
            root.types.Overlap.Yes => {},
        }
    }

    // The subjects share a common instance; the impls are still disjoint if
    // either carries a bound the common instance provably violates.
    let a_subject = [a_for].concat(a_args);
    let b_subject = [b_for].concat(b_args);
    if (
        !bounds_hold_at_common_instance(db, pkg_id, a, "a", vars, bindings, a_subject, aliases)
            || !bounds_hold_at_common_instance(db, pkg_id, b, "b", vars, bindings, b_subject, aliases)
    ) {
        return root.types.Overlap.No;
    }
    result
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::bounds_hold_at_common_instance @ d9be6853b
// Whether every bound of `rule` could hold at the common instance the
// unifier produced: false as soon as a bound whose subject the unifier
// pinned to a forced ground type is provably unsatisfiable. A bound whose
// subject is still a variable is undecidable in an open world (assumed
// satisfiable).
function bounds_hold_at_common_instance(
    db: root.hir.Db,
    pkg_id: int,
    rule: ImplData,
    prefix: string,
    vars: root.types.ParamTy[],
    bindings: root.types.TypeBindings,
    subject: root.types.Ty[],
    aliases: map<root.types.DeclName, root.types.Ty>,
) -> bool throws never {
    // Each of this impl's params, resolved to the ground type it takes at
    // the common instance (following the unifier's binding chains).
    let param_witnesses: root.types.TypeBindings = {};
    for (let j = 0; j < rule.generic_params.length(); j += 1) {
        param_witnesses[rule.generic_params[j].0]
            = root.types.chase_var(
                root.types.TyTypeVar { param: renamed_var(prefix, j) },
                vars,
                bindings,
            );
    }

    for (let i = 0; i < rule.generic_params.length(); i += 1) {
        let (let param_name, let bounds) = rule.generic_params[i];
        if (bounds.length() == 0) {
            continue;
        }
        let var_i = renamed_var(prefix, i);
        // Non-principal (union-cover) binding: the witness is arbitrary;
        // don't disprove.
        if (
            subject.some((t) -> {
                root.types.var_under_union(var_i, t)
            })
        ) {
            continue;
        }
        let witness = param_witnesses[param_name];
        // An unpinned witness (still a coherence var, or not fully realized)
        // is undecidable in an open world.
        if (root.types.contains_bound_typevar(witness, vars) || !root.types.realized(witness)) {
            continue;
        }
        // A single provably-unsatisfied bound makes the impls disjoint here,
        // concluded only when the instantiated bound is fully realized.
        for (let declared in bounds) {
            let bound = root.types.map_tys(declared, (t) -> {
                root.types.substitute_ty(t, param_witnesses)
            });
            if (
                root.types.tys(bound).every((t) -> {
                    root.types.realized(t)
                })
                    && get_implements_block(db, pkg_id, witness, bound, aliases) == null
            ) {
                return false;
            }
        }
    }
    true
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::renamed_var @ d9be6853b
// Fresh unification parameter for the `idx`-th generic param of the impl on
// side `prefix`.
function renamed_var(prefix: string, idx: int) -> root.types.ParamTy throws never {
    root.types.ParamTy { index: idx, name: `__coherence_${prefix}_${idx}` }
}

// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs::renamed_subject @ d9be6853b
// The impl's subject (for-type and interface args) normalized (CNF) with
// its generic params renamed to side-`prefix` unification variables.
// Associated bindings are interface outputs, not part of overlap.
function renamed_subject(
    rule: ImplData,
    prefix: string,
    enum_variants: root.types.EnumVariants,
) -> (root.types.Ty, root.types.Ty[]) throws never {
    let rename: root.types.TypeBindings = {};
    for (let i = 0; i < rule.generic_params.length(); i += 1) {
        rename[rule.generic_params[i].0] = root.types.TyTypeVar { param: renamed_var(prefix, i) };
    }
    let for_ty = root.types.nf(root.types.substitute_ty(rule.for_ty_pattern, rename), enum_variants);
    let args = rule.interface_args.map((arg) -> {
        root.types.nf(root.types.substitute_ty(arg, rename), enum_variants)
    });
    (for_ty, args)
}
