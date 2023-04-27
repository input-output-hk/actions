# IOG Shared GitHub Actions

## base action

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

## haskell action

This action will install ghc and cabal as needed

```
- name: Install Haskell
  uses: input-output-hk/actions/haskell@latest
  with:
    ghc-version: ${{ matrix.ghc }}
    cabal-version: 3.10.1.0
    pacman-packages: ... # more pacman package to install
```