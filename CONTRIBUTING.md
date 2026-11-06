# Contributing

Bug reports and pull requests are welcome. This is a personal project, so replies can take a few days.

- **Bugs:** use the issue form, with the output of `ephemeral-report`.
- **Security problems:** see [SECURITY.md](SECURITY.md), not an issue.
- **Changes:** open an issue first for anything bigger than a fix, so we can agree on it before you spend the time.

## Pull requests

- One feature per file under `modules/`, added to the shared modules as described in [Customizing](docs/customizing.md#how-its-organized). No imports between files.
- Add a line to `CHANGELOG.md` under the next version. Anything that breaks existing machines goes first, under Breaking, with what to do about it.
- Update the docs page that describes what you changed.
- Run the checks from [Working on this repo](docs/development.md) and turn on the git hooks. CI runs the same checks, and the boot tests once the maintainer adds the `boot-test` label.
- No machine files or secrets. The hooks and CI refuse `settings.json`, `hardware-configuration.nix`, keys and tokens.

By contributing you agree that your work is released under the [MIT License](LICENSE).
