// port: baml_compiler2_hir_ty/src/interfaces/coherence.rs @ d9be6853b
//
// Ported so far: the data type and stub the type checker's message layer
// (`check_types.baml`) reads.

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
// dependency closure, each pair containing an impl owned by `pkg_id`.
function package_coherence_diagnostics(
    db: root.hir.Db,
    pkg_id: int,
) -> CoherenceViolation[] throws never {
    baml.sys.panic("package_coherence_diagnostics: not ported")
}
