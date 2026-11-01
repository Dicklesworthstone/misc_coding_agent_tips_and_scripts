## Permanent CI/automation policy: DSR only

GitHub Actions must NEVER be used for ANY purpose in this project. Do not create, enable, dispatch, rerun, or rely on GitHub Actions workflows, whether they use GitHub-hosted runners or self-hosted runners registered with Actions. This is permanent policy, not a billing, quota, or outage workaround.

Use [DSR (Doodlestein Self-Releaser)](https://github.com/Dicklesworthstone/doodlestein_self_releaser) directly for CI, checks, builds, tests, releases, deployment automation, scheduled jobs, and other automation. DSR is the execution path, not a fallback after trying Actions. Existing workflow YAML may remain as input for local DSR/`act` execution; that does not authorize execution through GitHub Actions. Do not delete those definitions merely to enforce this policy. Keep all existing quality gates and evidence requirements when routing work through DSR.

