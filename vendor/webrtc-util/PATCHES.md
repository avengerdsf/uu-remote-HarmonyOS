# webrtc-util 0.8.1 vendor patch

Upstream webrtc-util 0.8.1 depends on `nix 0.26`, whose Linux/Android cfg
assumptions do not compile for the `aarch64-unknown-linux-ohos` target.
This vendored copy changes only the dependency declaration:

```toml
[target."cfg(not(windows))".dependencies.nix]
version = "0.29"
features = ["net"]
```

`nix 0.29` contains explicit `target_env = "ohos"` handling. The only
webrtc-util code using nix is `src/ifaces/ffi/unix/mod.rs`; its
`getifaddrs`/`SockaddrStorage` calls are unchanged in 0.29. No source files
were edited.
