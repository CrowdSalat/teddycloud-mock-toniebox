# syntax=docker/dockerfile:1

# ── Build stage ───────────────────────────────────────────────────────────────
# Build inputs are exactly go.mod, cmd/ and internal/. Copying them per directory
# keeps the build fail-closed: a new top-level path has to be added here on
# purpose instead of silently riding along inside a layer.
FROM docker.io/library/golang:1.26-bookworm AS builder

WORKDIR /src

# The module has no dependencies, so there is nothing to download and no go.sum
# to verify — `go mod download` would be a no-op that only adds a network round
# trip. The manifest is still copied first so a dependency added later does not
# silently arrive unverified.
COPY go.mod ./
COPY cmd/ ./cmd/
COPY internal/ ./internal/

# CGO off gives a static binary, which is what lets the runtime stage be scratch.
# -trimpath keeps build paths out of the binary; -s -w drops the symbol table and
# DWARF, worth ~30% on a tool whose stack traces are read by humans anyway.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /mock-toniebox ./cmd/mock-toniebox

# ── Runtime stage ─────────────────────────────────────────────────────────────
# scratch, not alpine: the binary is statically linked, so there is nothing to
# link against and no need for a shell or a package manager. This image is a
# protocol client — it opens TLS connections and reads HTTP — and needs no
# certificates, no CA bundle and no writable paths, because the box identity is
# generated in-process at startup.
FROM scratch

COPY --from=builder /mock-toniebox /mock-toniebox

LABEL org.opencontainers.image.source=https://github.com/CrowdSalat/teddycloud-mock-toniebox
LABEL org.opencontainers.image.description="A simulated Toniebox: speaks the box side of the teddyCloud protocol so a figurine cycle can be driven without hardware"

# 65534:0 rather than 65534:65534. The GID 0 is what makes this runnable under
# OpenShift's restricted-v2 and restricted-v3 SCCs, where the runtime UID is
# assigned by the platform and the GID is always 0. Nothing above needs to write,
# so no chown or chmod is required — and a hardcoded UID would be wrong anyway.
USER 65534:0

# The binary is PID 1 directly. It handles SIGTERM itself in the control server's
# shutdown path, and it is not a shell script, so there is nothing for an init
# process to reap or forward. (The shim image needs tini because it supervises
# PulseAudio and Soloist as child processes; this one has no children.)
ENTRYPOINT ["/mock-toniebox"]
CMD ["--addr", ":9095"]