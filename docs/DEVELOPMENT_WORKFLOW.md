# Development workflow

Tests run on your machine, not on GitHub. `just ci` is the CI; it
signs the commit on GitHub (`gh signoff`) when green, and `main` only
accepts signed commits.

## Start a feature

```sh
git checkout -b feat/<feature-identifier>
just run [folder]
just test
```

## Finish a feature

```sh
git push
just ci
```

## Merge into main

Open a Pull Request. It can be merged once `just ci` has signed its
last commit.

Only the owner can push to `main` directly (fast-forward of a signed
branch).

## Release (owner)

The work ships from a `release/X.Y.Z` branch — the one it was done on,
or a feature branch renamed once it is the release.

```sh
git push -u origin release/X.Y.Z
just ci
just release
```

`just release` takes the version from the branch name and refuses any
other branch, or a head `just ci` hasn't signed. It commits the version
into `meson.build`, the metainfo and the README and signs that commit
without a second run of the suite, having checked that nothing else
changed since the tested one; pushes the branch straight onto `main`,
so a `main` someone moved meanwhile refuses it before anything is
touched; pushes the tag, and deletes the branch. GitHub builds
`Opus.flatpak` and attaches it to the release.

## One-time setup

```sh
gh extension install basecamp/gh-signoff
flatpak install flathub org.flatpak.Builder
```

On GitHub, a ruleset on `main`: require the `signoff` status check,
and require a pull request — with the owner on the bypass list, which
is what allows the fast-forward push above and nothing else.
