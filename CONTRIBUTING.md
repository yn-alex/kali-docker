# Contributing

Thanks for helping. Changes go through issues and pull requests on
https://github.com/yn-alex/kali-docker.

## Proposing a change

1. Open an issue for bugs or larger ideas, or go straight to a pull request for small fixes.
2. Fork the repo, create a branch, make your change.
3. Read `AGENTS.md` first: it explains the layout and the gotchas that broke things before.
4. Open a pull request against `main` and describe what changed and why.

## Before you open a pull request

- Build the image you changed and run the smoke test:
  `docker build --target <cli|gui> -t kali-test .` then `tests/smoke.sh <cli|gui> kali-test`.
- Run `shellcheck` on every shell script you touched and fix its findings.
- Keep LF line endings in scripts (see `.gitattributes`); CRLF breaks the container start.
- Update `README.md` when a command, variable, port or tag changes.
- Never put passwords, tokens or personal data in the repo.

CI builds and tests every pull request but publishes nothing.
