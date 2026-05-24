# findings: gosec HIGH (G122) — TOCTOU in `gen/nvml/generateapi.go`

## Summary

One gosec **HIGH severity** finding surfaced by the baseline run. It is in
a build-time code generator, not in the runtime library, so the practical
attack surface is narrow — but it should be reviewed and either remediated
or annotated with intent.

## Finding

```
gen/nvml/generateapi.go:263
G122 (CWE-367): Filesystem operation in filepath.Walk/WalkDir callback
uses race-prone path; consider root-scoped APIs (e.g. os.Root) to prevent
symlink TOCTOU traversal (Confidence: MEDIUM, Severity: HIGH)
```

The flagged statement is `content, err := os.ReadFile(path)` where `path`
comes from a `filepath.WalkDir` callback. The risk: between the time
`WalkDir` reports the directory entry and the time `os.ReadFile` opens it,
a symlink could be swapped in pointing somewhere unexpected. A malicious
write to the working directory between `WalkDir` resolution and `ReadFile`
could redirect the read.

## Where it runs and who triggers it

`gen/nvml/generateapi.go` is the post-processing tool that rewrites
c-for-go's raw cgo bindings into go-nvml's interface-shaped public API
(`pkg/nvml/zz_generated.api.go`). It runs:

- Only at binding-regeneration time, invoked from the project's
  `Makefile` (`make bindings`).
- Against the developer's working copy of `pkg/nvml/`, not user input.
- In environments controlled by whoever is regenerating bindings.

So the threat model is "an attacker who can already write to your source
tree" — they already have arbitrary code execution. The TOCTOU window
adds nothing in practice.

## Recommended remediation

Pick one:

1. **Annotate and document** — cheapest, matches the threat model:

   ```go
   //nolint:gosec // G122: dev-time codegen tool, path comes from controlled
   //               WalkDir, threat model assumes trusted source tree.
   content, err := os.ReadFile(path)
   ```

2. **Migrate to `os.Root`** (Go 1.24+) — defense in depth:

   ```go
   root, err := os.OpenRoot(genDir)
   if err != nil { ... }
   defer root.Close()
   // walk via root.FS() and read via root.Open()
   ```

   The repo's `go.mod` declares `go 1.20`, so this requires bumping the
   minimum supported Go version.

3. **Re-stat after open** — middle ground, no Go version bump:

   ```go
   f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
   ```

   `O_NOFOLLOW` refuses to traverse the final symlink. Doesn't protect
   against substituting a regular file, but covers the more common
   misconfiguration.

Recommended: option 1 with a tracking comment, since the file is not in
the production runtime path. If the codegen is ever wired into a CI
pipeline that consumes externally-contributed paths, revisit and switch
to option 2.
