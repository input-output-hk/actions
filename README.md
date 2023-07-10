# IOG Shared GitHub Actions

## `base` action

This action will install the system dependencies we have:

- libsodium
- libsecp256k1
- libblst

See [iohk-nix/releases](https://github.com/input-output-hk/iohk-nix/releases/tag/latest)

```
- name: Install system dependencies
  uses: input-output-hk/actions/base@latest
  with:
    use-sodium-vrf: false # default is true
```

## `devx` action

This GitHub Action let you run commands into [the slightly opinionated `devx` shell](https://github.com/input-output-hk/devx) for Cardano-Haskell projects. The action takes the following inputs:

| Key | Description | Default value |
| - | - | - |
| `platform` | Specifies the architecture and operating system for the build. Accepted values are `x86_64-linux`, `x86_64-darwin`, `aarch64-linux`, or `aarch64-darwin`. | `x86_64-linux` |
| `target-platform` | Indicates the target platform for the build, which can be native, static (`-static`), Windows (`-windows`), or JavaScript (`-js`). | native (empty string) |
| `compiler-nix-name` | Specifies the GHC version to use. The version should be provided without dots, for example, GHC 8.10.7 should be written as `ghc8107`. | `ghc961` |
| `minimal` | A Boolean input to decide whether to include `hlint` and HLS in the build. Set to `false` to include these tools. | `true` |
| `iog` | Another Boolean input that, when set to `true`, will include `libsodum`, `libsecp256k1`, and `libblst` in the build. | `false` |

Here's how you might utilize this action in your workflow:

```yaml
- name: Build
  uses: input-output-hk/actions/base@latest
  with:
    platform: 'x86_64-linux'
    target-platform: '-windows'
    compiler-nix-name: 'ghc8107'
    minimal: false
    iog: true
- name: Build
  shell: devx {0}
  run: |
    cabal update
    cabal build
```

In this example, the action is configured to build on an `x86_64-linux` host platform for a Windows target. The GHC version used is 8.10.7, and it's set to perform a non-minimal build (including `hlint` and HLS). The `iog` option is set to `true` to include `libsodum`, `libsecp256k1`, and `libblst`.

## `haskell` action

This action will install ghc and cabal as needed

```
- name: Install Haskell
  uses: input-output-hk/actions/haskell@latest
  with:
    ghc-version: ${{ matrix.ghc }}
    cabal-version: 3.10.1.0
    pacman-packages: ... # more pacman package to install
```
