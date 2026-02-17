# scan-repo

A comprehensive security scanner that runs multiple industry-standard tools against a repository and produces a single, unified Markdown (or HTML) report. Designed to give developers and security teams a complete SCA + SAST + IaC picture in one command.

---

## What it does

`scan-repo` orchestrates five specialised scanners in a single pass:

| Scanner | Category | Finds |
|---------|----------|-------|
| **Semgrep** | SAST + Secrets | Code vulnerabilities, insecure patterns, hardcoded secrets |
| **Trivy** | SCA + IaC | CVEs in dependencies, Dockerfile/IaC misconfigurations |
| **OSV-Scanner** | SCA | CVEs via Google's Open Source Vulnerability database |
| **Grype** | SCA | CVEs in dependencies and container images |
| **npm audit** | SCA | Vulnerabilities in Node.js packages |
| **retire.js** | SCA | Known-vulnerable JavaScript libraries |
| **license-checker** | Compliance | Open-source license inventory |

Supported lockfile formats: `package-lock.json`, `yarn.lock`, `requirements.txt`, `Pipfile.lock`, `poetry.lock`, `Gemfile.lock`, `go.sum`, `Cargo.lock`, `pom.xml`, `build.gradle` and more.

---

## Quick start

```bash
# Install all tools
./install.sh --yes

# Scan the current directory, produce a Markdown report
scan-repo --markdown

# Scan a specific repo with all report formats
scan-repo --all-formats -o ./reports /path/to/repo
```

---

## Installation

### macOS

```bash
# Clone or download this repository, then:
./install.sh
```

Homebrew is required. Install it from [brew.sh](https://brew.sh) if you don't have it.

### Linux

Supported distributions: Ubuntu / Debian, RHEL / CentOS / Rocky / AlmaLinux, Fedora, Arch.

```bash
./install.sh
```

Run with `sudo` if your user does not have sudo rights, or run as root.

#### Non-interactive (CI/CD, Docker)

```bash
./install.sh --yes
```

#### Install to a custom directory (no root needed)

```bash
mkdir -p ~/.local/bin
./install.sh --yes --prefix ~/.local/bin
# Ensure ~/.local/bin is on your PATH:
export PATH="$HOME/.local/bin:$PATH"
```

### Windows (via WSL)

`scan-repo` is a bash script and runs inside **WSL 2** (Windows Subsystem for Linux).

1. Open **PowerShell as Administrator**
2. Run the PowerShell installer:

```powershell
.\install.ps1
```

This installs WSL 2 with Ubuntu, then runs `install.sh` inside it automatically.

If WSL is already set up:

```powershell
.\install.ps1 -SkipWslInstall -AssumeYes
```

After installation, use `scan-repo` from a WSL terminal or call it from PowerShell:

```powershell
# Windows drives are at /mnt/<letter>/ inside WSL
wsl -- scan-repo --markdown /mnt/c/Users/you/project
```

### Installer options

```
./install.sh [OPTIONS]

  -y, --yes              Skip confirmation prompts
  --prefix DIR           Install binaries to DIR (default: /usr/local/bin)
  --skip-semgrep         Skip Semgrep
  --skip-trivy           Skip Trivy
  --skip-osv             Skip OSV-Scanner
  --skip-grype           Skip Grype
  --skip-node            Skip Node.js and npm tools
  --skip-scan-repo       Skip installing the scan-repo command itself
  -h, --help             Show help
```

---

### Adding scan-repo to your PATH

`install.sh` copies `scan-repo` to `/usr/local/bin` by default, which is already on every system's `$PATH` — no further action is needed for a standard install.

If you used a custom `--prefix`, or downloaded `scan-repo` manually without running the full installer, run the dedicated script:

```bash
./add-to-environment
```

It auto-detects the right install location based on your permissions:

| Scenario | Where it installs | Requires |
|----------|-------------------|----------|
| Running as root or sudo available | `/usr/local/bin` (system-wide) | sudo |
| No root/sudo access | `~/.local/bin` (current user only) | nothing |

You can also choose explicitly:

```bash
./add-to-environment --system   # force /usr/local/bin  (needs sudo)
./add-to-environment --user     # force ~/.local/bin    (no sudo)
./add-to-environment --yes      # skip confirmation prompt
```

The script updates the correct shell config file (`~/.bashrc`, `~/.zshrc`, or `~/.config/fish/config.fish`) automatically and verifies the command is reachable before exiting. If you see a "not yet reachable" warning, open a new terminal or run `source ~/.bashrc`.

---

## Usage

```
scan-repo [OPTIONS] [DIRECTORY]
```

`DIRECTORY` defaults to the current directory.

### Scan options

| Flag | Description |
|------|-------------|
| `--skip-semgrep` | Skip Semgrep SAST scan |
| `--skip-trivy` | Skip Trivy scan |
| `--skip-osv` | Skip OSV-Scanner |
| `--skip-grype` | Skip Grype scan |
| `--skip-npm` | Skip npm audit and retire.js |
| `--skip-license` | Skip license-checker |
| `--only-sast` | Run Semgrep only |
| `--only-deps` | Run dependency scanners only (no SAST) |

### Output options

| Flag | Description |
|------|-------------|
| `-o DIR`, `--output DIR` | Output directory (default: `./security-reports`) |
| `--markdown` | Generate a Markdown report (`REPORT-<timestamp>.md`) |
| `--html` | Generate an HTML report |
| `--all-formats` | Generate both Markdown and HTML |
| `-f FORMAT` | Short form: `json`, `html`, `markdown`, `all` |
| `--verbose` | Show debug output |
| `--quiet` | Suppress all output except errors |

### CI/CD options

| Flag | Description |
|------|-------------|
| `--ci` | Minimal output + machine-readable exit codes |
| `--fail-on-critical` | Exit code 1 if any Critical findings |
| `--fail-on-high` | Exit code 1 if any High findings |

### Examples

```bash
# Scan current directory (JSON output only, default)
scan-repo

# Scan a specific directory with Markdown report
scan-repo --markdown /path/to/repo

# Full report in all formats, custom output directory
scan-repo --all-formats -o ./security-reports .

# SAST only (fast, no network calls for dependency DBs)
scan-repo --only-sast --markdown

# Dependency scanning only, skip SAST
scan-repo --only-deps --markdown

# CI pipeline — fail build on critical or high issues
scan-repo --ci --fail-on-critical --fail-on-high

# Quiet mode for scripting, specific directory
scan-repo --quiet --json -o /tmp/scan /path/to/repo

# Skip individual tools
scan-repo --skip-grype --skip-license --markdown .
```

---

## Report format

Running with `--markdown` produces a `REPORT-<timestamp>.md` file with these sections:

```
# Security Scan Report

## Summary              ← Critical / High / Medium / Low totals
## Semgrep SAST        ← Code vulnerabilities, secrets (table)
## Trivy               ← CVEs per dependency (table)
## Grype               ← CVEs per dependency (table)
## OSV-Scanner         ← CVEs per dependency (table)
## Dockerfile / IaC    ← Misconfiguration findings (table)
## npm Audit           ← Advisory per package (table with URLs)
## Next Steps          ← Prioritised remediation guidance
```

Each JSON report (`semgrep-*.json`, `trivy-*.json`, etc.) is also preserved in the output directory for downstream processing or archiving.

### Severity mapping

| Tool | Severity labels |
|------|----------------|
| Semgrep | `ERROR` → Critical, `WARNING` → High, `INFO` → Medium |
| Trivy | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` |
| Grype | `Critical`, `High`, `Medium`, `Low` |
| OSV-Scanner | Listed by advisory ID (see individual CVE details) |
| npm audit | `critical`, `high`, `moderate` (→ Medium), `low` |

The **Summary** table aggregates counts across all tools, so a vulnerability found by both Trivy and Grype will appear in each tool's section but counted once per tool in the summary. Cross-reference the individual tables to deduplicate if needed.

---

## CI/CD integration

### GitHub Actions

```yaml
name: Security Scan

on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install scan-repo tools
        run: ./install.sh --yes
        working-directory: /path/to/scan-repo

      - name: Run security scan
        run: |
          scan-repo \
            --ci \
            --fail-on-critical \
            --markdown \
            --all-formats \
            -o ./security-reports \
            .

      - name: Upload report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: security-report
          path: security-reports/
```

### GitLab CI

```yaml
security-scan:
  image: ubuntu:22.04
  script:
    - apt-get update -qq && apt-get install -y curl git
    - ./install.sh --yes
    - scan-repo --ci --fail-on-critical --markdown -o ./security-reports .
  artifacts:
    when: always
    paths:
      - security-reports/
    expire_in: 30 days
```

---

## Requirements

| Tool | Minimum version | Required |
|------|----------------|----------|
| bash | 4.0+ | Yes |
| jq | 1.6+ | Yes (JSON parsing) |
| curl | any | Yes (downloads) |
| Semgrep | 1.0+ | Core scanner |
| Trivy | 0.40+ | Core scanner |
| OSV-Scanner | 1.9+ | Core scanner |
| Grype | 0.60+ | Core scanner |
| Node.js | 16+ | npm audit, retire.js, license-checker |

---

## File structure

```
scan-repo/
├── scan-repo              ← Main scanner script (install to /usr/local/bin)
├── install.sh             ← Linux / macOS / WSL installer (installs all tools + scan-repo)
├── install.ps1            ← Windows (PowerShell) installer (sets up WSL, then calls install.sh)
├── add-to-environment     ← Standalone PATH helper (use if scan-repo isn't found as a command)
├── README.md
└── security-reports/      ← Default output directory (created on first scan)
```

---

## Troubleshooting

**`scan-repo: command not found`**
Ensure `/usr/local/bin` (or your custom `--prefix`) is on your `PATH`:
```bash
export PATH="/usr/local/bin:$PATH"
# Add to ~/.bashrc or ~/.zshrc to make permanent
```

**OSV-Scanner produces empty output**
Make sure you have a supported lockfile in your repository (e.g. `package-lock.json`, `requirements.txt`, `go.sum`). OSV-Scanner only scans known lockfile formats.

**Semgrep rules download slowly**
Semgrep fetches rules from the registry on first use. You can pre-download them:
```bash
semgrep --config=p/security-audit --config=p/secrets /tmp/empty-dir 2>/dev/null || true
```

**npm audit fails with `ENOLOCK`**
Run `npm install` in your project first to generate `package-lock.json`, then re-run the scan.

**Permission denied installing tools**
Run the installer with `sudo ./install.sh` or use `--prefix ~/.local/bin` for a user-level install.

**Windows: `wsl: command not found`**
WSL is not installed. Run `.\install.ps1` in an Administrator PowerShell to set it up automatically.

---

## Version

`scan-repo` v1.0.0
