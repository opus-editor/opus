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

```sh
just release X.Y.Z
```

Bumps the version, runs `just ci`, fast-forwards `main`, pushes the
tag. GitHub builds `Opus.flatpak` and attaches it to the release.

## One-time setup

```sh
gh extension install basecamp/gh-signoff
flatpak install flathub org.flatpak.Builder
```

On GitHub, a ruleset on `main`: require the `signoff` status check,
and require a pull request — with the owner on the bypass list, which
is what allows the fast-forward push above and nothing else.
