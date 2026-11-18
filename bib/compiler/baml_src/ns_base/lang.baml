// port: baml_base/src/lang.rs @ d9be6853b (LangPackage, LangRoots)
//
// The language packages: the stdlib packages the compiler itself names.

enum LangPackage {
  // The core package: builtin companion classes, `baml.panics`, `baml.ops`.
  Baml
  // Reflection: `reflect.Type` and the sealed `reflect.<Kind>` views.
  Reflect
  // LLM functions and clients.
  Ai
  // `log.info` / `debug` / `warn` / `error`, compiler intrinsics.
  Log
  // Invocation tracing options for the reserved `$trace` argument.
  Trace
  // The test harness.
  Testing
  // Assertions for test bodies.
  Assert
  // Provider packages: the client classes `"provider/model"` constructs.
  Openai
  Anthropic
  Typesafeai
  Google
  Aws
  Vercel
  ClaudeCode
}

// port: LangPackage::ALL. Every package, in declaration order.
const LANG_PACKAGES: LangPackage[] = [
  LangPackage.Baml, LangPackage.Reflect, LangPackage.Ai, LangPackage.Log, LangPackage.Trace,
  LangPackage.Testing, LangPackage.Assert, LangPackage.Openai, LangPackage.Anthropic,
  LangPackage.Typesafeai, LangPackage.Google, LangPackage.Aws, LangPackage.Vercel,
  LangPackage.ClaudeCode,
];

// port: LangPackage::manifest_name
function lang_package_manifest_name(package: LangPackage) -> string throws never {
  match (package) {
    LangPackage.Baml => "baml",
    LangPackage.Reflect => "reflect",
    LangPackage.Ai => "ai",
    LangPackage.Log => "log",
    LangPackage.Trace => "trace",
    LangPackage.Testing => "testing",
    LangPackage.Assert => "assert",
    LangPackage.Openai => "openai",
    LangPackage.Anthropic => "anthropic",
    LangPackage.Typesafeai => "typesafeai",
    LangPackage.Google => "google",
    LangPackage.Aws => "aws",
    LangPackage.Vercel => "vercel",
    LangPackage.ClaudeCode => "claude_code",
  }
}

// port: LangPackage::from_manifest_name
function lang_package_from_manifest_name(name: string) -> LangPackage? throws never {
  LANG_PACKAGES.find((package) -> { lang_package_manifest_name(package) == name })
}

// port: lang.rs::LangRoots. Where each language package is installed (a root
// id), if it is.
class LangRoots {
  roots: map<LangPackage, int>,
  // Speed: `roots` inverted (root id -> package), built on first use and
  // reset whenever `roots` changes (`set`). An int-keyed lookup is much
  // cheaper than an enum-keyed one on the VM.
  by_root: map<int, LangPackage>?,

  // Install `package` at `root_id`.
  function set(self, package: LangPackage, root_id: int) -> void throws never {
    self.roots[package] = root_id;
    self.by_root = null;
  }

  function inverted(self) -> map<int, LangPackage> throws never {
    let built = self.by_root;
    if (built != null) {
      return built;
    }
    let out: map<int, LangPackage> = {};
    for (let package in self.roots.keys()) {
      out[self.roots[package]] = package;
    }
    self.by_root = out;
    out
  }

  function get(self, package: LangPackage) -> int? throws never {
    self.roots.get(package)
  }

  // Whether `root` is the installed `package`.
  function is_(self, package: LangPackage, root_id: int) -> bool throws never {
    self.inverted().get(root_id) == package
  }

  // Which language package `root` is, if it is one.
  function package_of(self, root_id: int) -> LangPackage? throws never {
    self.inverted().get(root_id)
  }
}
