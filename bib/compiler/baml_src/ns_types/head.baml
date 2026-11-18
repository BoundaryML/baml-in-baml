// port: baml_type/src/head.rs @ d9be6853b
//
// Nothing here is ported:
// - `Head` is a bundle of Rust bounds (`Clone + Ord + Eq + Hash + Debug`)
//   that a nominal head must satisfy. Every family member here is headed by
//   DeclName, so there is no head parameter to bound.
// - `TaggedTypeName` is the head of the runtime boundary layers (sys-ops,
//   SAP, output-format rendering): a `TypeTag` identity plus a
//   `DeclarationName` spelling. Both live in deferred files (typetag.rs,
//   declaration_name.rs), and the type checker never builds one.
