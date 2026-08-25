# Contribution Guidelines

- **Objective:** Provision private agile Silicon Mac OS for Deployment of AI- and LLM based Services.
- **Target Audience:** Teams, Small Organisations and Individuals
- **Success Metrics:** [How do we know it works? To be defined]

Provisioning is based on `ansible` and `brew` . The projects supports multiple deployment environments.

## Architecture Overview

The Provisioning System supports local and remote execution over `ssh`.

The Machine is provisioned using `ansible` and `brew`. It covers application deployments and node configuration.

Operating System is Silicon Mac OS.

### Goals

- Agility: Rapid iteration and deployment of AI- and LLM based applications with minimal friction.
- Simplicity
- Composability
- Observability
- Resource Efficiency

### Non Goals

### Decisions

## Building and Running

The main development workflow entrypoints are provided by the `Makefile` and include tasks for testing, validation and deployment.

The default `help` target provides help for all provided tasks.

The `justfile` is a separate, narrower entrypoint: day-to-day operations on host
services that Ansible provisions but does not converge on demand (e.g.
`just hermes-update`). `just --list` shows the recipes. Anything to do with
linting, testing or provisioning belongs in the `Makefile`, not here.

Before submitting any changes, it is crucial to validate them running:

```bash
make preflight
```

These commands will lint the code, format code and run the tests.

## Git Repo

The main branch for this project is called "main".

## Languages and Frameworks

When contributing to this codebase, please prioritize clear, readable, and maintainable code. The `Makefile` provides all major workflow entrypoints. The default `help` target provides help for all provided tasks.

### Shell Scripts

- **Formatting**: Use `make shell-fmt` to format your code, which runs `shfmt`.
- **Linting**: `shellcheck` is used for linting. Run `make shell-lint` to lint your code.
- **Structure**: Scripts to be provisioned on the node are in the `assets/bin` folder.

### Ansible

Ansible uses the inventory specified by the `ANSIBLE_INVENTORY` environment variable. For `local` development, this is set to `inventory`, for remote provisioning over `ssh` it is `inventory-ssh`.

The primary declarative `ansible` vars configuration file is `./default.config.yml`. It covers packages from various sources, such as `brew`, `npm`, `pip`, `gem` and `composer`.

The `main.yml` playbook includes roles and tasks for installing packages, configuring the system, and deploying applications and services.

- _Framework_ Ansible tests are based on **Molecule**.
- **Linting**: `ansible-lint` is used for linting. Configuration is in `.ansible-lint`. Do not run it directly. Run it using `make ansible-lint`.
- **Validation**: Use `make ansible-playbook-check` to perform a dry run of the playbook.
- **Structure**: The main playbook is `main.yml`. Roles are located in `roles/` and variables in `group_vars/`. Dependencies are managed in `requirements.yml`.
- **Package Management**: `ansible-galaxy` is used for Ansible roles.

## Comments policy

Only write high-value comments if at all. Avoid talking to the user through comments.

## Agent Collaboration Protocol

When available, you must use the Agents

- **Sysiphus** (Analyst)
- **Hephaestus** (Implementer)
- **Librarian** (Researcher)
- **Oracle** (Senior Researcher)
- **Momus** (Critic)

### The Golden Rule: PRD-First Development

Before executing any task, you MUST read `PRD.md`.

- Every implementation must map to a Feature ID (e.g., `[F-01]`).
- If a user request contradicts the `PRD.md`, you must flag the conflict and ask for a "Requirement Update" before writing code.

### The Implementation Loop (Sisyphus & Hephaestus)

When assigned a feature via `ulw` (ultrawork):

1. **Analyze:** Read the specific Feature ID in `PRD.md`.
2. **Plan:** Outline the files to be created/modified.
3. **Execute:** Write the code (Hephaestus).
4. **Verify:** Run tests or use Momus to critique the implementation.
5. **Document:** Upon completion, you MUST update `PROGRESS.md`.

### Documentation Standards

#### Updating PROGRESS.md

You are responsible for maintaining the `PROGRESS.md` file. After every major logic change:

- **Status Update:** Change the status icon (🕒 -> 🏗 -> ✅).
- **Log Entry:** Add a single line to the "Recent Agent Activity Log" using the format:
  `> **[AgentName] (YYYY-MM-DD):** [Action performed and result].`

#### Updating PRD.md

- Only the **Librarian** or **Oracle** agents should modify the "Technical Spec" sections of the PRD based on research.
- If a human provides a new requirement verbally, suggest an update to `PRD.md` before proceeding.

### Conflict Resolution

If the **Momus** agent (Critic) rejects a PR based on a requirement in the PRD, **Hephaestus** must prioritize fixing the logic over arguing the point, unless the PRD itself is technically flawed.
