// port: baml_db/src/db.rs @ d9be6853b (stdlib_layout, install_stdlib, and the
// workspace root a compile adds), for a BAML-compiled `Db`.
//
// deviation: the stdlib sources are read from disk under `stdlib_dir` (the
// fork's `baml_language/crates/baml_builtins2/baml_std`); Rust embeds them in
// the binary.

class ManifestPackage {
  name: string,
  prelude: bool?,
}

class ManifestDependency {
  path: string,
}

// The parts of a stdlib `baml.toml` the layout reads.
class Manifest {
  package: ManifestPackage,
  dependencies: map<string, ManifestDependency>?,
}

// port: db.rs::StdlibPackage
class StdlibPackage {
  name: string,
  prelude: bool,
  // (edge name, target package name)
  dependencies: (string, string)[],
}

// port: db.rs::stdlib_layout. The stdlib packages from their manifests, in
// dependency order (Kahn), keeping manifest order among the ready set.
function stdlib_layout(stdlib_dir: string) -> StdlibPackage[] throws baml.errors.Io | baml.errors.ParseError {
  let pending = root.builtins.STDLIB_PACKAGE_NAMES.map((name) -> { stdlib_package(stdlib_dir, name) });
  let ordered: StdlibPackage[] = [];
  let placed: map<string, bool> = {};
  while (pending.length() > 0) {
    let ready = pending.find((package) -> {
      package.dependencies.every((edge) -> { placed.has(edge.1) })
    }) ?? baml.sys.panic("stdlib dependency cycle");
    placed[ready.name] = true;
    ordered.push(ready);
    pending = pending.filter((package) -> { package.name != ready.name });
  }
  ordered
}

// One stdlib package's manifest, its edges resolved to package names.
function stdlib_package(stdlib_dir: string, name: string) -> StdlibPackage throws baml.errors.Io | baml.errors.ParseError {
  let text = baml.fs.read(`${stdlib_dir}/${name}/baml.toml`);
  let table = baml.toml.Table.parse(text) catch (e) {
    baml.toml.ParseError => baml.sys.panic(`stdlib package \`${name}\` has an invalid baml.toml`),
  };
  let manifest = baml.json.to<Manifest>(baml.toml.item_to_json(table)) catch_all (e) {
    _ => baml.sys.panic(`stdlib package \`${name}\` has an unexpected baml.toml`),
  };
  let edges = manifest.dependencies ?? {};
  StdlibPackage {
    name: name,
    prelude: manifest.package.prelude ?? false,
    // `../<pkg>` from `<builtin>/<name>` names the sibling package `<pkg>`.
    dependencies: edges.keys().map((edge) -> { (edge, edges[edge].path.split("/").at(1) ?? "") }),
  }
}

// port: db.rs::install_stdlib (from source). One `Stdlib` root per package,
// created in dependency order with its manifest edges; then the language
// roots and the prelude every later root receives.
function install_stdlib(db: root.hir.Db, stdlib_dir: string) -> void throws baml.errors.Io | baml.errors.ParseError {
  let roots: map<string, int> = {};
  for (let package in stdlib_layout(stdlib_dir)) {
    let id = add_root(
      db,
      `<builtin>/${package.name}`,
      root.base.SourceRootKind.Stdlib,
      package.name,
      package.dependencies.map((edge) -> { root.base.Dependency { name: edge.0, root: roots[edge.1] } }),
    );
    roots[package.name] = id;
    for (let file in root.builtins.STDLIB_FILES.filter((f) -> { f.0 == package.name })) {
      add_file(db, id, `<builtin>/${package.name}/${file.1}`, baml.fs.read(`${stdlib_dir}/${package.name}/${file.1}`));
    }
    if (package.prelude) {
      db.prelude.push(root.base.Dependency { name: package.name, root: id });
    }
  }
  for (let lang in root.base.LANG_PACKAGES) {
    let id = roots.get(root.base.lang_package_manifest_name(lang));
    if (id != null) {
      db.lang_roots.roots[lang] = id;
    }
  }
}

// A source root: a package, with the prelude edges unless it is stdlib.
function add_root(
  db: root.hir.Db,
  path: string,
  kind: root.base.SourceRootKind,
  self_name: string?,
  dependencies: root.base.Dependency[],
) -> int throws never {
  let id = db.roots.length();
  let edges = if (kind == root.base.SourceRootKind.Stdlib) { dependencies } else { db.prelude.concat(dependencies) };
  db.roots.push(root.base.SourceRoot {
    id: id,
    path: path,
    kind: kind,
    self_name: self_name,
    files: [],
    exclude_tests: false,
    dependencies: edges,
  });
  db.root_order.push(id);
  id
}

// Register a file in root `root_id`.
function add_file(db: root.hir.Db, root_id: int, path: string, text: string) -> int throws never {
  let id = db.files.length();
  db.files.push(root.base.SourceFile { id: id, text: text, path: path, root: root_id });
  db.roots[root_id].files.push(id);
  id
}

// A Db holding the stdlib, then one workspace root holding `files`
// (path -> text), the way `reflect.Package.compile` compiles them.
function project_db(stdlib_dir: string, files: map<string, string>) -> root.hir.Db throws baml.errors.Io | baml.errors.ParseError {
  let db = root.hir.Db.new();
  install_stdlib(db, stdlib_dir);
  if (files) {
    let workspace = add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    for (let path in files.keys()) {
      add_file(db, workspace, path, files[path]);
    }
  }
  db
}
