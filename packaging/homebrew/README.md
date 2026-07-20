# Homebrew packaging

`e3.rb.in` is a template for the custom tap formula. It installs release archives produced by:

```sh
just release 0.1.0
```

Before publishing a release:

1. Build the same version on `Darwin-arm64` and `Darwin-x86_64`.
2. Upload both archives from `dist/` to the GitHub release tagged `v<version>`.
3. Copy this template to `Formula/e3.rb` in the tap repository.
4. Replace `@VERSION@` and both SHA-256 placeholders. The formula uses the project's MIT license.
5. Run:

```sh
brew style Formula/e3.rb
brew audit --strict --new Formula/e3.rb
brew install --build-from-source Formula/e3.rb
brew test e3
```

The release executable statically links libghostty-vt. SDL3 and SDL3_ttf remain Homebrew runtime dependencies.

The template targets a custom tap. Submission to `homebrew/core` additionally requires a source-only build with all Ghostty/Zig resources declared and is not covered by this template.
