# Homebrew packaging

`e3.rb.in` is the CLI/TTY formula template. `e3-app.rb.in` is the macOS application cask template. Release archives are produced by:

```sh
just release-app 0.1.0
```

Before publishing a release:

1. Build the same version on `Darwin-arm64` and `Darwin-x86_64`.
2. Upload the CLI `.tar.gz` and application `-app.zip` archives from `dist/` to the GitHub release tagged `v<version>`.
3. Render the formula directly into the tap repository (the script fills both checksums):

```sh
scripts/render-homebrew-formula.sh \
  0.1.0 \
  dist/e3-0.1.0-Darwin-arm64.tar.gz \
  dist/e3-0.1.0-Darwin-x86_64.tar.gz \
  ../homebrew-e3/Formula/e3.rb
```

4. Render the cask into the tap repository:

```sh
scripts/render-homebrew-cask.sh \
  0.1.0 \
  dist/e3-0.1.0-Darwin-arm64-app.zip \
  dist/e3-0.1.0-Darwin-x86_64-app.zip \
  ../homebrew-e3/Casks/e3.rb
```

5. Validate both:

```sh
brew style Formula/e3.rb Casks/e3.rb
brew audit --strict --new boyswan/e3/e3
brew install --cask Casks/e3.rb
brew test e3
```

Once the tap is pushed, users install with:

```sh
brew tap boyswan/e3
brew trust boyswan/e3
brew install --cask e3                  # macOS application
brew install e3                         # optional CLI/TTY formula
```

The release executable statically links libghostty-vt. SDL3 and SDL3_ttf remain Homebrew runtime dependencies.

The template targets a custom tap. Submission to `homebrew/core` additionally requires a source-only build with all Ghostty/Zig resources declared and is not covered by this template.
