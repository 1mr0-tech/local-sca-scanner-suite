# scan-repo

> A comprehensive security scanner that orchestrates multiple industry-standard tools against a repository and produces a single unified report. One command. Complete SCA + SAST + IaC picture.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## What it does

`scan-repo` runs nine specialised scanners in a single pass:

| Scanner | Category | What it finds |
|---------|----------|---------------|
| **Semgrep** | SAST + Secrets | Code vulnerabilities, insecure patterns, hardcoded secrets |
| **Trivy** | SCA + IaC | CVEs in dependencies, Dockerfile / IaC misconfigurations, secrets |
| **OSV-Scanner** | SCA | CVEs via Google's Open Source Vulnerability database |
| **Grype** | SCA | CVEs in dependencies and container images |
| **npm audit** | SCA | Vulnerabilities in Node.js / Next.js packages (`package-lock.json`) |
| **yarn audit** | SCA | Vulnerabilities in yarn.lock projects |
| **retire.js** | SCA | Known-vulnerable JavaScript libraries |
| **pip-audit** | SCA | CVEs in Python dependencies (`requirements.txt`, Pipfile, poetry) |
| **OWASP Dependency-Check** | SCA | CVEs in Java dependencies (pom.xml, Gradle, JARs, WARs, EARs) |
| **license-checker** | Compliance | Open-source license inventory for Node.js projects |

**Supported lockfile formats:** `package-lock.json`, `yarn.lock`, `requirements.txt`, `Pipfile.lock`, `poetry.lock`, `Gemfile.lock`, `go.sum`, `Cargo.lock`, `pom.xml`, `build.gradle` and more.

Every scan automatically writes `SCAN_RESULTS.md` in the directory where you run it — no flags needed.

---

## Quick start

```bash
# Install all tools
./install.sh --yes

# Scan the current directory — SCAN_RESULTS.md is written here automatically
scan-repo

# Also generate a timestamped report in ./security-reports/
scan-repo --markdown

# Full scan with all report formats, custom output directory
scan-repo --all-formats -o ./reports /path/to/repo
```

---

## Installation

### macOS

```bash
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
export PATH="$HOME/.local/bin:$PATH"
```

### Windows (via WSL 2)

`scan-repo` is a bash script and runs inside **WSL 2** (Windows Subsystem for Linux).

1. Open **PowerShell as Administrator**
2. Run:

```powershell
.\install.ps1
```

This installs WSL 2 with Ubuntu, then runs `install.sh` inside it automatically.

If WSL is already set up:

```powershell
.\install.ps1 -SkipWslInstall -AssumeYes
```

After installation, use `scan-repo` from a WSL terminal or from PowerShell:

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
  --skip-java            Skip OWASP Dependency-Check (Java)
  --skip-scan-repo       Skip installing the scan-repo command itself
  -h, --help             Show help
```

---

## Adding scan-repo to your PATH

`install.sh` copies `scan-repo` to `/usr/local/bin` by default, which is already on every system's `$PATH` — no further action needed for a standard install.

If you used a custom `--prefix`, or downloaded `scan-repo` manually, run the dedicated helper:

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
| `--skip-npm` | Skip npm/yarn audit and retire.js |
| `--skip-java` | Skip OWASP Dependency-Check (Java) |
| `--skip-license` | Skip license-checker |
| `--only-sast` | Run Semgrep only |
| `--only-deps` | Run dependency scanners only (no SAST) |

### Output options

| Flag | Description |
|------|-------------|
| `-o DIR`, `--output DIR` | Output directory (default: `./security-reports`) |
| `--markdown` | Generate a timestamped `REPORT-<timestamp>.md` in the output directory |
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
# Scan current directory — SCAN_RESULTS.md written here automatically
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

# Skip Java scanning on non-Java projects (faster)
scan-repo --skip-java --markdown

# Skip individual tools
scan-repo --skip-grype --skip-license --markdown .
```

---

## Report format

Every scan automatically generates `SCAN_RESULTS.md` in the **current directory** where you run `scan-repo`. No flags needed.

Running with `--markdown` additionally generates a timestamped `REPORT-<timestamp>.md` in the output directory (`./security-reports` by default).

Both files contain the same sections:

```
# Security Scan Report

## Summary              ← Critical / High / Medium / Low totals
## Semgrep SAST        ← Code vulnerabilities, secrets (table)
## Trivy               ← CVEs per dependency (table)
## Grype               ← CVEs per dependency (table)
## OSV-Scanner         ← CVEs per dependency (table)
## Dockerfile / IaC    ← Misconfiguration findings (table)
## npm Audit           ← Advisory per package (table with URLs)
## yarn Audit          ← Advisory per package for yarn.lock projects
## pip-audit           ← Python dependency CVEs (table)
## OWASP DC            ← Java CVEs (pom.xml, Gradle, JARs/WARs)
## Next Steps          ← Prioritised remediation guidance
```

Each JSON report (`semgrep-*.json`, `trivy-*.json`, etc.) is also preserved in the output directory for downstream processing or archiving.

### Severity mapping

| Tool | Severity labels |
|------|----------------|
| Semgrep | `ERROR` → Critical, `WARNING` → High, `INFO` → Medium |
| Trivy | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` |
| Grype | `Critical`, `High`, `Medium`, `Low` |
| OSV-Scanner | Listed by advisory ID |
| npm audit | `critical`, `high`, `moderate` (→ Medium), `low` |
| yarn audit | `critical`, `high`, `moderate` (→ Medium), `low` |
| pip-audit | CVE / GHSA IDs (counted as High in summary) |
| OWASP Dependency-Check | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` |

The **Summary** table aggregates counts across all tools. A vulnerability found by both Trivy and Grype will appear in each tool's section and be counted once per tool in the summary.

---

## OWASP Dependency-Check — Java scanning

OWASP Dependency-Check requires Java 11+ and downloads the NVD CVE database on first run (~300 MB). Subsequent runs use the cached database and complete in seconds.

### Speeding up database updates (optional)

Without an API key, the initial NVD download is rate-limited and can take 15–30 minutes. With a free NVD API key it completes in 3–5 minutes.

Get a free key at: [nvd.nist.gov/developers/request-an-api-key](https://nvd.nist.gov/developers/request-an-api-key)

Then set it in your shell — **never put it in code or config files**:

```bash
# Add to ~/.bashrc or ~/.zshrc
export NVD_API_KEY="your-key-here"
```

`scan-repo` reads this environment variable automatically when running OWASP Dependency-Check. The key is never written to any file.

To pre-seed the database manually (one time):

```bash
dependency-check --updateonly --nvdApiKey "$NVD_API_KEY"
```

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
        env:
          NVD_API_KEY: ${{ secrets.NVD_API_KEY }}
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
  variables:
    NVD_API_KEY: $NVD_API_KEY   # set in GitLab CI/CD variables
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

> **Tip:** Store `NVD_API_KEY` as a masked CI/CD secret — never hardcode it in pipeline files.

---

## Requirements

| Tool | Minimum version | Role |
|------|----------------|------|
| bash | 4.0+ | Required |
| jq | 1.6+ | Required (JSON parsing) |
| curl | any | Required (downloads) |
| Semgrep | 1.0+ | Core SAST scanner |
| Trivy | 0.40+ | Core SCA + IaC scanner |
| OSV-Scanner | 1.9+ | Core dependency scanner |
| Grype | 0.60+ | Core dependency scanner |
| Node.js | 16+ | npm audit, yarn audit, retire.js, license-checker |
| pip-audit | 2.0+ | Python dependency scanning |
| Java | 11+ | OWASP Dependency-Check (Java projects only) |
| OWASP Dependency-Check | 9.0+ | Java SCA |

---

## Known limitations

| Scanner | Limitation |
|---------|-----------|
| **Trivy** | Requires a resolved lockfile for full dependency coverage. Maven/Gradle projects without a lockfile may show fewer results; OSV-Scanner and OWASP DC cover the gap. |
| **OSV-Scanner** | Only recognises known lockfile formats. Projects with unusual setups may need `--recursive` (already enabled). |
| **OWASP Dependency-Check** | First run requires downloading the full NVD database. Java 11+ required. Use `NVD_API_KEY` env var for faster updates. |
| **pip-audit** | Scans declared dependencies only. Vendored packages not in a requirements file will be missed. |
| **npm audit** | Requires `package-lock.json`. Run `npm install` first if the lockfile is absent. |
| **Semgrep** | Rulesets are fetched from the registry on first use. Pre-download with `semgrep --config=p/security-audit /tmp/empty 2>/dev/null`. |

---

## File structure

```
scan-repo/
├── scan-repo              ← Main scanner script (install to /usr/local/bin)
├── install.sh             ← Linux / macOS / WSL installer
├── install.ps1            ← Windows (PowerShell) installer — sets up WSL then calls install.sh
├── add-to-environment     ← Standalone PATH helper
├── README.md
├── CHANGELOG.md
├── LICENSE
└── security-reports/      ← Default output directory (created on first scan, gitignored)
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
Semgrep fetches rules from the registry on first use. Pre-download them:
```bash
semgrep --config=p/security-audit --config=p/secrets /tmp/empty-dir 2>/dev/null || true
```

**npm audit fails with `ENOLOCK`**
Run `npm install` in your project first to generate `package-lock.json`, then re-run the scan.

**OWASP Dependency-Check is slow on first run**
The NVD database download takes 15–30 min without an API key. Get a free key at [nvd.nist.gov](https://nvd.nist.gov/developers/request-an-api-key) and set `export NVD_API_KEY="your-key"` before scanning.

**Trivy shows no vulnerabilities for a Java project**
Trivy needs a resolved dependency lockfile. For Maven projects, run `mvn dependency:resolve` first, or rely on OWASP Dependency-Check and OSV-Scanner which handle `pom.xml` directly.

**Permission denied installing tools**
Run the installer with `sudo ./install.sh` or use `--prefix ~/.local/bin` for a user-level install.

**Windows: `wsl: command not found`**
WSL is not installed. Run `.\install.ps1` in an Administrator PowerShell to set it up automatically.

---

## Contributing

Contributions are welcome. Please open an issue or pull request on GitHub.

- Keep changes focused — one fix or feature per PR
- Test against both a Node.js and a Java project before submitting
- Update `CHANGELOG.md` with your change

---

## License

MIT — see [LICENSE](LICENSE).
