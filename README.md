# teddycloud-mock-toniebox

A simulated Toniebox. It speaks the box side of the teddyCloud protocol, so a
figurine can be placed on and lifted off a teddyCloud server without the hardware.

```
mock-toniebox ──RTNL frames──▶ teddyCloud ──GET /stream──▶ your shim
     │                            │
     └──── GET /v2/content ───────┘
```

That is the whole point. A Toniebox is the only actor that both emits the RTNL
frames teddyCloud turns into SSE **and** pulls the content that makes teddyCloud's
ffmpeg call a shim's `/stream`. Mock it and the entire chain runs for real, with
your code under test untouched.

## Image

```bash
podman run --rm -p 9095:9095 \
  ghcr.io/crowdsalat/teddycloud-mock-toniebox:latest \
  --teddycloud https://teddycloud:443 \
  --sse http://teddycloud:80 \
  --uid E00403500EEA4BF2
```

No credentials, no volume mounts, no pairing. The box identity is generated
in-process at startup.

`--teddycloud` is the box-facing HTTPS listener, because only that one is behind
the client-certificate gate. `--sse` is the web listener, which is a different
port — `/api/sse` does not exist on the API listener.

## Driving it

Everything is a `POST` to the control surface. The control page at
<http://localhost:9095/> has a button for each action.

```bash
./scripts/cycle.sh place          # put a figurine on the box
./scripts/cycle.sh lift           # take it off
./scripts/cycle.sh cycle 10       # 10 place/lift cycles, with the measurement table
./scripts/cycle.sh report         # measurements so far, as JSON
./scripts/cycle.sh log teddycloud # what teddyCloud made of it
```

Or with `podman exec`:

```bash
podman exec mock-toniebox curl -X POST localhost:9095/control/place
```

`place` and `lift` are the ones that matter. They produce exactly the two signals
a shim's control path is built from: a placement produces `TagValid`, and a lift
produces `playback=stopped`.

## Why the flags exist

Box behaviour that real firmware could demonstrate differently is exposed as flags
rather than baked in, and the active set is printed at startup and stamped into
every report. A measurement is only attributable alongside the assumptions that
produced it — if the mock silently hardcodes one guess about firmware, it becomes
a machine for proving that guess.

The ones worth knowing:

| Flag | Default | Why |
|---|---|---|
| `--firmware` | `cc3200` | CC3200 and ESP32 use different log2 function codes for the same event |
| `--range-offset` | `zero` | `zero` re-requests from byte 0; `resume` continues from the last byte. This is the single biggest behavioural difference |
| `--speed` | `1.0` | consumption rate as a multiple of real time. 0 means no pacing; to stop reading without disconnecting, use `cycle.sh stall` |
| `--mac` | `00aabbccdd00` | becomes teddyCloud's overlay id, so runs are reproducible |
| `--pad-field6` | `0` | extra filler bytes in the RTNL payload, to check teddyCloud tolerates a longer one |

Full list: `--help`. Rationale for each, and the protocol notes behind them, in
[`docs/mock-toniebox-design.md`](docs/mock-toniebox-design.md).

## What it can and cannot tell you

It verifies your shim given a specified box behaviour. It does **not** verify the
specified box behaviour. Whether real firmware skips between chapters, tolerates
the per-chapter framing, or cross-fades at boundaries is hardware behaviour that
no mock can answer.

It also cannot distinguish "my code is wrong" from "teddyCloud is wrong". Every
report is therefore attributable to a teddyCloud version, and where teddyCloud's
behaviour turned out to be surprising it is recorded in §16 of the design doc
rather than smoothed over.

## Development

```bash
go test ./...
golangci-lint run ./...
hadolint Containerfile

podman build -t localhost/mock-toniebox:dev -f Containerfile .
```

No third-party dependencies. The RTNL protobuf messages are small and proto2, so
they are hand-encoded rather than generated — adding `protoc` and a protobuf
dependency to a test instrument is not a trade worth making.

## Credits

Design and protocol analysis derived from reading teddyCloud v0.7.0
(`78c3b38`). Extracted from
[`teddycloud-spotify-radio-shim`](https://github.com/CrowdSalat/teddycloud-spotify-radio-shim),
where it was built to make a stream-silence defect reproducible.