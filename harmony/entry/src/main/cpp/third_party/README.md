# Third-party native dependencies

## libopus 1.4

- Source: <https://downloads.xiph.org/releases/opus/opus-1.4.tar.gz>
- SHA-256 of the release tarball: `c9b32b4253be5ae63d1ff16eea06b94b5f0f2951b7a02aceef58e3a3ce49c51f`
- License: BSD 3-Clause (`opus/COPYING`); the surrounding project remains GPL-3.0-or-later.
- Local changes: none. Only files required by the upstream CMake build are
  vendored (`CMakeLists.txt`, `cmake/`, `include/`, `src/`, `silk/`, `celt/`,
  `*_sources.mk`, `*_headers.mk`, `configure.ac`, `Makefile.am`,
  `package_version`, `COPYING`, `AUTHORS`). Tests, programs, documentation and
  generated build systems are omitted.
- Build options used by `entry/src/main/cpp/CMakeLists.txt`: static library,
  no testing/programs/install modules, `OPUS_DISABLE_INTRINSICS=ON`. Opus is
  used only to decode RTP Opus payloads at 48 kHz stereo into S16 PCM for
  OHAudio; intrinsics are disabled so the OHOS cross build has no runtime CPU
  feature detection dependency.

Upstream license text is kept verbatim in `opus/COPYING`. Do not remove it
when packaging a HAP or source release.
