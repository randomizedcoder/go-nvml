# findings: nilerr (26) — false positives against `Return` enum

## Summary

`nilerr` reports 26 sites under `pkg/nvml/`, all with the message:

> `error is nil (line N) but it returns error`

**None of these are bugs.** Every site is the same idiom, and the root
cause is that go-nvml's `Return` type implements the `error` interface
even though its zero value (`SUCCESS`) is the library's idiomatic
nil-equivalent. `nilerr` doesn't understand domain-specific nil
sentinels and flags every "return ret inside `if ret == SUCCESS`" branch
as suspicious.

## The pattern

All 26 sites look like this (sample from `pkg/nvml/device.go:993`):

```go
func (device nvmlDevice) GetEncoderSessions() ([]EncoderSessionInfo, Return) {
    var sessionCount uint32 = 1
    for {
        sessionInfos := make([]EncoderSessionInfo, sessionCount)
        ret := nvmlDeviceGetEncoderSessions(device, &sessionCount, &sessionInfos[0])  // line 997
        if ret == SUCCESS {
            return sessionInfos[:sessionCount], ret                                   // line 999 — nilerr fires here
        }
        if ret != ERROR_INSUFFICIENT_SIZE {
            return nil, ret
        }
        sessionCount *= 2
    }
}
```

`Return` is declared in `pkg/nvml/return.go` and implements `error`:

```go
func (r Return) Error() string {
    return errorStringFunc(r)
}
```

So `nilerr` treats every `Return`-returning function the way it would
treat one returning Go's `error`. The conditional `if ret == SUCCESS` reads
to `nilerr` as the "no error" branch (because `SUCCESS == Return(0)`,
syntactically the zero value), and returning a typed-non-nil `ret`
inside that branch is what the linter flags.

In NVML semantics, returning `SUCCESS` IS the convention for "no error".
The code is correct.

## All 26 sites

```
pkg/nvml/device.go:999     pkg/nvml/device.go:1453    pkg/nvml/device.go:2012
pkg/nvml/device.go:1041    pkg/nvml/device.go:1474    pkg/nvml/device.go:2033
pkg/nvml/device.go:1090    pkg/nvml/device.go:1926    pkg/nvml/device.go:2097
pkg/nvml/device.go:1105    pkg/nvml/device.go:1946    pkg/nvml/system.go:59
pkg/nvml/device.go:1120    pkg/nvml/device.go:1966    pkg/nvml/unit.go:97
pkg/nvml/device.go:1144    pkg/nvml/device.go:1992    pkg/nvml/vgpu.go:350
pkg/nvml/device.go:1159
pkg/nvml/device.go:1174
pkg/nvml/device.go:1198
pkg/nvml/device.go:1213
pkg/nvml/device.go:1228
pkg/nvml/device.go:1422
pkg/nvml/vgpu.go:376
pkg/nvml/vgpu.go:407
```

## Recommended remediation

Three options, ordered by least to most invasive:

1. **Disable `nilerr` in `nix/golangci/golangci.yml`** when run against
   go-nvml — the cost (no signal anywhere) is high if real `nilerr` bugs
   are ever introduced. **Not recommended.**

2. **Annotate each site** with `//nolint:nilerr // Return.SUCCESS is nil
   equivalent`. 26 lines of nolint comments. Tedious but explicit.
   **Reasonable.**

3. **Return the literal `SUCCESS` instead of `ret`** inside the success
   branch:

   ```go
   if ret == SUCCESS {
       return sessionInfos[:sessionCount], SUCCESS  // was: ret
   }
   ```

   This sidesteps the linter (returning `SUCCESS` directly is "returning
   the nil sentinel literal", which nilerr accepts) and is arguably
   slightly clearer at the call site. 26 one-line edits.
   **Recommended.**

Note that option 3 changes generated code if any of these sites were
emitted by c-for-go — but `pkg/nvml/device.go`, `system.go`, `unit.go`,
and `vgpu.go` are all hand-written wrapper layers, not c-for-go output,
so it is safe to edit them directly.

## Why we don't auto-fix in this baseline

The plan for this nix-branch pass scoped fix work to "HIGH severity /
real-bug findings." These are not real bugs (they are linter
misclassifications), so they stay in the report as a documented batch
rather than mixed into the flake-setup commit. A follow-up PR can land
the 26 small edits in `pkg/nvml/{device,system,unit,vgpu}.go` if you
want a clean tier-1 run.
