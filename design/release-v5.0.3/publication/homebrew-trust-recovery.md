# Homebrew trust recovery for the immutable 5.0.3 release

The first public Homebrew lifecycle, run 41173520133, passed the exact public
asset/tap gate and Intel lifecycle. Its macOS 26 ARM job stopped at `brew info`
before installation because Homebrew required explicit third-party Cask trust.
Latest and Pages were correctly skipped. This is a CI compatibility issue;
the five-platform candidate installation matrix remains successful.

Homebrew's [official Tap Trust documentation](https://docs.brew.sh/Tap-Trust)
requires explicit trust for non-official items and recommends trusting the
specific Cask used by automation. The recovery adds that scoped trust after
the existing tap commit, version and PKG checksum checks, supports older
Homebrew, and cleans the invocation-owned trust state. No trust requirement,
checksum, source or CI gate is disabled.

The post-publication CI repair requires advancing and refreezing `main` for
validation/deployment. The annotated `v5.0.3` tag remains on
`aaa50d1ee1e8b04ded88706bb8e65e035034d7b7`, candidate run 41171291351, and
all four published installer assets remain byte-identical. They are never
rebuilt or replaced. The recovery commit changes no App/helper source,
release artwork or marketing copy.

Require successful Headless push CI on the new deployment commit before a
fresh public Homebrew dispatch. Then require both architectures, automatic
Latest promotion and Pages success from that same new commit. Record equality
of the original and deployment artwork/product trees. Public artwork checks
use the deployment SHA; package provenance and local installation checks keep
the original immutable release SHA. Final run IDs and tree proof are recorded
in the release completion evidence.
