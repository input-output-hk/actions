# cabal-gild action

This `run-cabal-gild` GitHub Action helps to ensure that your Haskell project is
formatted with [cabal-gild](https://github.com/tfausak/cabal-gild). The action
tries to find all Cabal source code files in your repository and fails if any
of them are not formatted. In case of failure it prints the diff between the
actual contents of the file and its formatted version.

## Example usage

In the simple case all you need to do is to add this step to your job:

```yaml
- uses: input-output-hk/actions/run-cabal-gild@v1
  with:
    version: "1.7.0.1"
```

The `1.7.0.1` should be replaced with the version of cabal-gild you want to use.  See
[cabal-gild releases](https://github.com/tfausak/cabal-gild/releases) for all cabal-gild versions.
If you don't specify this cabal-gild `version` input, the latest version of
cabal-gild will be used.
