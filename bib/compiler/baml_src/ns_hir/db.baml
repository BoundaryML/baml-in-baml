// port: baml_compiler2_hir/src/lib.rs::Db, loc.rs, the `#[salsa::interned]`
// ids of scope.rs and namespace.rs, and the salsa machinery they stand on
// @ d9be6853b
//
// Salsa, the BAML way (bib/IDIOMS.md, "Salsa"):
//   #[salsa::input]          -> a class in the Db's arrays, referred to by `id`
//   #[salsa::interned] Loc   -> an `int` id into a `LocArena` on the Db
//   #[salsa::tracked] fn q   -> `function q(db: Db, key: int)`, cached in
//                               `db.memo.q` (a `Memo`)
// There is no incrementality: one compile builds one Db.

// A cache for one query: its results by key.
class Memo<V> {
  values: map<int, V>,

  function new() -> Memo<V> throws never {
    Memo { values: {} }
  }

  // The cached result for `key`, computing and storing it on first use.
  function get(self, key: int, compute: () -> V throws never) -> V throws never {
    if (self.values.has(key)) {
      return self.values[key];
    }
    let value = compute();
    self.values[key] = value;
    value
  }
}

// port: loc.rs::{FunctionLoc, ClassLoc, ...}'s fields, and ScopeId's. An item
// (or scope) of a file: the file's id and the item's file-local id.
class ItemLoc {
  file: int,
  id: int,
}

// Interned `ItemLoc`s of one kind: equal locs get equal `int` ids.
class LocArena {
  locs: ItemLoc[],
  // file -> local id -> interned id
  index: map<int, map<int, int>>,

  function new() -> LocArena throws never {
    LocArena { locs: [], index: {} }
  }

  function intern(self, file: int, id: int) -> int throws never {
    if (!self.index.has(file)) {
      self.index[file] = {};
    }
    let by_id = self.index[file];
    if (by_id.has(id)) {
      return by_id[id];
    }
    let interned = self.locs.length();
    self.locs.push(ItemLoc { file: file, id: id });
    by_id[id] = interned;
    interned
  }

  function get(self, interned: int) -> ItemLoc throws never {
    self.locs[interned]
  }
}

// port: namespace.rs::NamespaceId's fields. A namespace of a package.
class NamespaceKey {
  package: int,
  path: string[],
}

// Interned `NamespaceKey`s.
class NamespaceArena {
  keys: NamespaceKey[],
  index: map<string, int>,

  function new() -> NamespaceArena throws never {
    NamespaceArena { keys: [], index: {} }
  }

  function intern(self, package: int, path: string[]) -> int throws never {
    let spelling = `${package}:${path.join(".")}`;
    if (self.index.has(spelling)) {
      return self.index[spelling];
    }
    let interned = self.keys.length();
    self.keys.push(NamespaceKey { package: package, path: path });
    self.index[spelling] = interned;
    interned
  }

  function get(self, interned: int) -> NamespaceKey throws never {
    self.keys[interned]
  }
}

// port: lib.rs::Db plus the concrete database's inputs (baml_db's
// ProjectDatabase). Everything a compile reads, and every cache.
class Db {
  files: root.base.SourceFile[],
  // port: SourceRootTable. Roots by id; `root_order` is the table order
  // (Stdlib < Dependency < Workspace < Dynamic).
  roots: root.base.SourceRoot[],
  root_order: int[],
  lang_roots: root.base.LangRoots,
  // The edges every non-stdlib root receives: the prelude packages.
  prelude: root.base.Dependency[],
  // Interned ids (loc.rs, scope.rs, namespace.rs).
  function_locs: LocArena,
  class_locs: LocArena,
  enum_locs: LocArena,
  interface_locs: LocArena,
  type_alias_locs: LocArena,
  let_locs: LocArena,
  impl_locs: LocArena,
  scopes: LocArena,
  namespaces: NamespaceArena,
  memo: Memos,
  // The tracked-query stack the type checker's cyclic queries share
  // (tracked.baml).
  cycles: Cycles,

  function new() -> Db throws never {
    Db {
      files: [],
      roots: [],
      root_order: [],
      lang_roots: root.base.LangRoots { roots: {} },
      prelude: [],
      function_locs: LocArena.new(),
      class_locs: LocArena.new(),
      enum_locs: LocArena.new(),
      interface_locs: LocArena.new(),
      type_alias_locs: LocArena.new(),
      let_locs: LocArena.new(),
      impl_locs: LocArena.new(),
      scopes: LocArena.new(),
      namespaces: NamespaceArena.new(),
      memo: Memos.new(),
      cycles: Cycles.new(),
    }
  }

  function file(self, id: int) -> root.base.SourceFile throws never {
    self.files[id]
  }

  function source_root(self, id: int) -> root.base.SourceRoot throws never {
    self.roots[id]
  }
}

// One cache per Rust `#[salsa::tracked]` query, keyed by the query's id
// argument (a file, root, loc, scope or namespace id; `workspace_roots`,
// which takes none, uses key 0). Generated once from the Rust signatures.
class Memos {
  // body.rs::function_body
  function_body: Memo<FunctionBody>,
  // body.rs::function_body_source_map
  function_body_source_map: Memo<root.ast.AstSourceMap?>,
  // body.rs::let_body
  let_body: Memo<LetBody>,
  // body.rs::let_body_source_map
  let_body_source_map: Memo<root.ast.AstSourceMap?>,
  // body_type_refs.rs::function_body_type_refs
  function_body_type_refs: Memo<BodyTypeRefs>,
  // body_type_refs.rs::let_body_type_refs
  let_body_type_refs: Memo<BodyTypeRefs>,
  // body_type_refs.rs::parameter_defaults_type_refs
  parameter_defaults_type_refs: Memo<BodyTypeRefs>,
  // file_package.rs::file_package
  file_package: Memo<PackageInfo>,
  // item_data/classes.rs::class_data
  class_data: Memo<ClassData>,
  // item_data/classes.rs::class_source_map
  class_source_map: Memo<ClassSourceMap>,
  // item_data/enumeration.rs::file_impls
  file_impls: Memo<int[]>,
  // item_data/enumeration.rs::class_impls
  class_impls: Memo<int[]>,
  // item_data/enums.rs::enum_data
  enum_data: Memo<EnumData>,
  // item_data/enums.rs::enum_source_map
  enum_source_map: Memo<EnumSourceMap>,
  // item_data/functions.rs::enclosing_type_generic_param_count
  enclosing_type_generic_param_count: Memo<int>,
  // item_data/functions.rs::function_data
  function_data: Memo<FunctionData>,
  // item_data/functions.rs::function_source_map
  function_source_map: Memo<FunctionSourceMap>,
  // item_data/functions.rs::function_llm_meta
  function_llm_meta: Memo<FunctionLlmMeta?>,
  // item_data/functions.rs::llm_prompt_spans
  llm_prompt_spans: Memo<root.ast.LlmPromptSpans?>,
  // item_data/functions.rs::llm_prompt_segments
  llm_prompt_segments: Memo<root.ast.TemplateSegment[]?>,
  // item_data/functions.rs::elaborated_function_data
  elaborated_function_data: Memo<ElaboratedFunctionData>,
  // item_data/functions.rs::elaborated_function_source_map
  elaborated_function_source_map: Memo<ElaboratedFunctionSourceMap>,
  // item_data/functions.rs::method_owner
  method_owner: Memo<MethodOwner?>,
  // item_data/functions.rs::function_has_body
  function_has_body: Memo<bool>,
  // item_data/functions.rs::is_required_interface_method
  is_required_interface_method: Memo<bool>,
  // item_data/functions.rs::method_interface_target
  method_interface_target: Memo<MethodInterfaceTarget?>,
  // item_data/functions.rs::method_interface_target_source_map
  method_interface_target_source_map: Memo<MethodInterfaceTargetSourceMap?>,
  // item_data/functions.rs::function_trace_hook
  function_trace_hook: Memo<string[]?>,
  // item_data/functions.rs::function_trace_hook_span
  function_trace_hook_span: Memo<root.syntax.TextRange?>,
  // item_data/impls.rs::impl_block_data
  impl_block_data: Memo<ImplBlockData>,
  // item_data/impls.rs::impl_block_source_map
  impl_block_source_map: Memo<ImplBlockSourceMap>,
  // item_data/interfaces.rs::interface_data
  interface_data: Memo<InterfaceData>,
  // item_data/interfaces.rs::interface_source_map
  interface_source_map: Memo<InterfaceSourceMap>,
  // item_data/lets.rs::let_data
  let_data: Memo<LetData>,
  // item_data/lets.rs::let_source_map
  let_source_map: Memo<LetSourceMap>,
  // item_data/scopes.rs::scope_owner
  scope_owner: Memo<ScopeOwner?>,
  // item_data/type_aliases.rs::type_alias_data
  type_alias_data: Memo<TypeAliasData>,
  // item_data/type_aliases.rs::type_alias_source_map
  type_alias_source_map: Memo<TypeAliasSourceMap>,
  // lib.rs::file_ast
  file_ast: Memo<FileAst>,
  // lib.rs::file_semantic_index
  file_semantic_index: Memo<FileSemanticIndex>,
  // namespace.rs::namespace_item_names
  namespace_item_names: Memo<string[]>,
  // namespace.rs::namespace_items
  namespace_items: Memo<NamespaceItems>,
  // package.rs::workspace_roots
  workspace_roots: Memo<int[]>,
  // package.rs::visible_packages
  visible_packages: Memo<int[]>,
  // package.rs::world_roots
  world_roots: Memo<int[]>,
  // package.rs::world_files
  world_files: Memo<int[]>,
  // package.rs::edge_table
  edge_table: Memo<(string, int)[]>,
  // package.rs::package_dependency_closure
  package_dependency_closure: Memo<int[]>,
  // package.rs::package_items
  package_items: Memo<PackageItems>,
  // signature.rs::function_signature
  function_signature: Memo<FunctionSignature>,
  // signature.rs::function_signature_source_map
  function_signature_source_map: Memo<SignatureSourceMap>,
  // signature.rs::function_parameter_defaults
  function_parameter_defaults: Memo<FunctionParameterDefaults>,
  // signature.rs::elaborated_function_signature
  elaborated_function_signature: Memo<ElaboratedFunctionSignature>,
  // signature.rs::elaborated_function_signature_source_map
  elaborated_function_signature_source_map: Memo<SignatureSourceMap>,

  function new() -> Memos throws never {
    Memos {
      function_body: Memo.new(),
      function_body_source_map: Memo.new(),
      let_body: Memo.new(),
      let_body_source_map: Memo.new(),
      function_body_type_refs: Memo.new(),
      let_body_type_refs: Memo.new(),
      parameter_defaults_type_refs: Memo.new(),
      file_package: Memo.new(),
      class_data: Memo.new(),
      class_source_map: Memo.new(),
      file_impls: Memo.new(),
      class_impls: Memo.new(),
      enum_data: Memo.new(),
      enum_source_map: Memo.new(),
      enclosing_type_generic_param_count: Memo.new(),
      function_data: Memo.new(),
      function_source_map: Memo.new(),
      function_llm_meta: Memo.new(),
      llm_prompt_spans: Memo.new(),
      llm_prompt_segments: Memo.new(),
      elaborated_function_data: Memo.new(),
      elaborated_function_source_map: Memo.new(),
      method_owner: Memo.new(),
      function_has_body: Memo.new(),
      is_required_interface_method: Memo.new(),
      method_interface_target: Memo.new(),
      method_interface_target_source_map: Memo.new(),
      function_trace_hook: Memo.new(),
      function_trace_hook_span: Memo.new(),
      impl_block_data: Memo.new(),
      impl_block_source_map: Memo.new(),
      interface_data: Memo.new(),
      interface_source_map: Memo.new(),
      let_data: Memo.new(),
      let_source_map: Memo.new(),
      scope_owner: Memo.new(),
      type_alias_data: Memo.new(),
      type_alias_source_map: Memo.new(),
      file_ast: Memo.new(),
      file_semantic_index: Memo.new(),
      namespace_item_names: Memo.new(),
      namespace_items: Memo.new(),
      workspace_roots: Memo.new(),
      visible_packages: Memo.new(),
      world_roots: Memo.new(),
      world_files: Memo.new(),
      edge_table: Memo.new(),
      package_dependency_closure: Memo.new(),
      package_items: Memo.new(),
      function_signature: Memo.new(),
      function_signature_source_map: Memo.new(),
      function_parameter_defaults: Memo.new(),
      elaborated_function_signature: Memo.new(),
      elaborated_function_signature_source_map: Memo.new(),
    }
  }
}
