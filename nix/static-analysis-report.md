# go-nvml Static Analysis Baseline Report

A baseline snapshot of every check the nix flake exposes, run against the
fresh `nix` branch with no prior cleanup. The goal is to (a) confirm the
pipeline produces real signal and (b) surface security and critical
correctness findings first.

## Run metadata

| Field | Value |
|---|---|
| Date (UTC) | 2026-05-24 |
| Branch | `nix` |
| Repo | `randomizedcoder/go-nvml` (fork of `NVIDIA/go-nvml`) |
| Base of `nix` | `60c51fd` (Merge PR #180 — update go) |
| Working tree | dirty (this branch's flake files + this report) |
| Go toolchain | `go1.26.3 linux/amd64` (from `pkgs.go_1_26`) |
| `go.mod` declares | `go 1.20` |
| nixpkgs lock | `2991645341…` (nixos-unstable, 2026-05-23) |
| golangci-lint | 2.12.2 |
| staticcheck | 2026.1 (v0.7.0) |
| gosec | 2.26.1 |
| govulncheck | 1.3.0, DB `https://vuln.go.dev` |

Reproduction:

```sh
for c in nix-fmt statix deadnix go-vet staticcheck gosec \
         golangci-lint-quick golangci-lint golangci-lint-comprehensive; do
  nix build -L .#checks.x86_64-linux.$c
done
nix run .#govulncheck-go-nvml
```

## Executive summary

| Check | Status | Issues | Wall-clock |
|---|---|---|---|
| `nix-fmt` | PASS | 0 | 2 s |
| `statix` | PASS | 0 | 1 s |
| `deadnix` | PASS | 0 | 1 s |
| `go-vet` | PASS | 0 | 12 s |
| `staticcheck` (standalone) | PASS | 0 | 19 s |
| `gosec` | FAIL | **11** (1 HIGH, 0 MED, 10 LOW) | 14 s |
| `govulncheck-go-nvml` (source mode) | PASS | 0 | ~30 s |
| `golangci-lint-quick` (Tier 0) | FAIL | 53 | 19 s |
| `golangci-lint` (Tier 1) | FAIL | 57 | 19 s |
| `golangci-lint-comprehensive` (Tier 2) | FAIL | 110 | 20 s |

The nix-side checks (`nix-fmt`, `statix`, `deadnix`) are clean by
construction. `go-vet`, standalone `staticcheck`, and `govulncheck` are all
green. Findings concentrate in three places: gosec's `G103` unsafe-pointer
audit, golangci-lint's `nilerr` (26 — every one is a false positive against
go-nvml's `Return` enum type, see findings doc), and staticcheck's `ST1003`
naming convention (50, all in c-for-go-derived public surface).

## Triage recommendation

1. **`gosec` G122 HIGH (1) — security audit.** `gen/nvml/generateapi.go:263`
   reads files inside a `filepath.WalkDir` callback (TOCTOU symlink-traversal
   risk). The file is a build-time code generator that runs in trusted
   environments, so the practical risk is low — annotate with
   `//nolint:gosec` + reason, or migrate to `os.Root`. See
   [`findings-gosec-high.md`](./findings-gosec-high.md).

2. **`nilerr` (26) — all false positives.** Every site is the same idiom:
   inside `if ret == SUCCESS { return ..., ret }`, returning `ret` (the
   SUCCESS sentinel) is the library's nil-equivalent for the `Return` type.
   `nilerr` doesn't understand the domain sentinel. See
   [`findings-nilerr-false-positives.md`](./findings-nilerr-false-positives.md)
   for the recommended remediation (annotate, or return `SUCCESS` literal,
   or `//nolint`).

3. **`gosec` G103 LOW (10) — unsafe-pointer audit hits.** All in cgo
   helper paths (`pkg/dl/dl*.go`, `pkg/nvml/cgo_helpers_static.go`,
   `pkg/nvml/device.go`, `pkg/nvml/vgpu.go`). These are deliberate
   cgo-to-Go bridges and the audit findings are advisory. Annotate.

4. **`staticcheck` ST1003 naming (50)** — c-for-go binding output uses
   `_v2`, `_v3` suffixes and `Id` casing. Renaming is a public-API break,
   so either leave alone, exclude ST1003 globally, or coordinate a major
   bump.

5. **`errcheck` (3), `unparam` (3), `gocritic` (5), `revive` (4),
   `perfsprint` (2), `unconvert` (2), `testifylint` (11)** — mostly
   mechanical, mostly in `gen/nvml/generateapi.go` (build tool) and
   examples. Defer.

## Detailed findings

### gosec — 11 issues (1 HIGH, 10 LOW)

```
gen/nvml/generateapi.go:263    G122 Filesystem op in filepath.WalkDir uses race-prone path (HIGH)
pkg/nvml/vgpu.go:371           G103 Use of unsafe calls (LOW)
pkg/nvml/device.go:3468        G103 (LOW)
pkg/nvml/device.go:3460        G103 (LOW)
pkg/nvml/device.go:3132        G103 (LOW)
pkg/nvml/device.go:3125        G103 (LOW)
pkg/nvml/device.go:2957        G103 (LOW)
pkg/nvml/device.go:2362        G103 (LOW)
pkg/nvml/device.go:2208        G103 (LOW)
pkg/nvml/device.go:2181        G103 (LOW)
pkg/nvml/device.go:1987        G103 (LOW)
```

Exclusions inherited from nebula's baseline: `-exclude=G101,G115,G204,G304,G306,G401,G501 -exclude-generated`. `G103` (audited unsafe) is kept on so cgo-bridge sites surface deliberately.

### golangci-lint tier 0 — quick (53 issues)

| Linter | Issues |
|---|---:|
| `staticcheck` | 50 (all `ST1003` naming) |
| `errcheck` | 3 |

The 50 `ST1003` findings cluster around `_v1`/`_v2` method-suffix and `Id`
vs `ID` casing in c-for-go output. These are all in the public API and
would be a breaking change to rename.

`errcheck` (3):

```
gen/nvml/generateapi.go:99     return value not checked (build tool)
pkg/nvml/nvml_test.go:52       return value not checked (test cleanup)
pkg/nvml/nvml_test.go:53       return value not checked (test cleanup)
```

### golangci-lint tier 1 — standard (57 issues)

Adds correctness-and-style linters on top of tier 0.

| Linter | Issues |
|---|---:|
| `nilerr` | 26 |
| `testifylint` | 11 |
| `gocritic` | 5 |
| `revive` | 4 |
| `errcheck` | 3 |
| `unparam` | 3 |
| `perfsprint` | 2 |
| `unconvert` | 2 |
| `gosec` | 1 |

(Note: tier 1 disables `staticcheck`'s `ST*` style rules, so the 50 tier-0
ST1003 issues do not appear here.)

**`nilerr` representative finding (every one is the same pattern):**

```
pkg/nvml/device.go:999    error is nil (line 997) but it returns error (nilerr)
```

The code is:

```go
ret := nvmlDeviceGetEncoderSessions(device, &sessionCount, &sessionInfos[0])
if ret == SUCCESS {
    return sessionInfos[:sessionCount], ret  // ← nilerr fires here
}
```

`Return` implements `error` (it has `Error() string`), so the linter
treats it like a Go `error` and complains that returning `ret` inside the
`ret == SUCCESS` branch is "returning a non-nil error after the nil check".
But in NVML's convention, `SUCCESS` (zero) IS the nil-equivalent — this is
the library's idiom. Not a bug. See
[`findings-nilerr-false-positives.md`](./findings-nilerr-false-positives.md).

### golangci-lint tier 2 — comprehensive (110 issues)

Adds style/complexity linters intended to surface long-term tech debt.

| New in tier 2 | Issues |
|---|---:|
| `revive` (now severity-warning) | 50 |
| `prealloc` | 2 |
| `exhaustive` | 1 |
| `gocyclo` | 1 |
| `misspell` | 1 |
| `nestif` | 1 |
| `whitespace` | 1 |

(The other linters' counts are the same as tier 1.)

### staticcheck (standalone) — 0 issues

`staticcheck ./...` with default checks (no `ST*` rules) is clean. This
contrasts with the 50 `ST1003` findings in golangci-lint's staticcheck
integration — they're style rules disabled by default in upstream
staticcheck, but enabled by golangci-lint's profile.

### govulncheck source-mode — 0 vulnerabilities

go-nvml's transitive dep graph is tiny (`google/uuid`, `stretchr/testify`,
`davecgh/go-spew`, `pmezard/go-difflib`, `yaml.v3`). No reachable CVEs.

### go-vet — clean

All packages including `pkg/nvml`, `pkg/dl`, `pkg/nvml/mock`,
`pkg/nvml/mock/dgxa100`, `gen/nvml`, and the four `examples/`.

### nix-fmt / statix / deadnix — clean

The flake's own `.nix` files round-trip through `nixfmt`, pass `statix
check`, and `deadnix --fail` reports no unused bindings.

## Generated-code exclusions

The flake's `nix/golangci/*.yml` configs exclude:

- `pkg/nvml/zz_generated.api.go` (custom generator, "Generated Code" header — not auto-detected)
- `pkg/nvml/types_gen.go` (cgo -godefs)
- `pkg/nvml/dynamicLibrary_mock.go` (moq)
- `pkg/nvml/mock/*.go` (moq, multiple files)

The c-for-go-generated files (`pkg/nvml/nvml.go`, `pkg/nvml/const.go`,
`pkg/nvml/doc.go`) carry standard `Code generated by …; DO NOT EDIT.`
headers and are auto-detected by golangci-lint's `generated: lax` setting.

The repo's existing `.golangci.yaml` is left untouched — the nix checks
pass their own `--config nix/golangci/*.yml`, so the IDE workflow is
unchanged.

## Repro one-liner

```sh
# All checks in parallel (mostly cached after first run)
nix flake check -L

# Or one at a time
nix build -L .#checks.x86_64-linux.golangci-lint-quick           # 53 issues
nix build -L .#checks.x86_64-linux.golangci-lint                 # 57 issues
nix build -L .#checks.x86_64-linux.golangci-lint-comprehensive   # 110 issues
nix build -L .#checks.x86_64-linux.staticcheck                   # 0
nix build -L .#checks.x86_64-linux.gosec                         # 11 issues
nix run .#govulncheck-go-nvml                                    # 0 CVEs
```
