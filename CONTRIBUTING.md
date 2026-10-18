# Contributing

- Keep the utility dependency-light and portable across Linux distributions.
- Quote shell variables and use `--` for paths.
- Never automatically trust signing keys downloaded from the same server as an ISO.
- Run `bash -n debian-downloader` and `bash tests/smoke-test.sh`.
- Describe tested distributions and Bash/curl versions in pull requests.
- Do not commit ISO images or other large binary files.
