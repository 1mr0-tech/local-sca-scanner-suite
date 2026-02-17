#!/usr/bin/env bash

###############################################################################
# scan-repo Installer
#
# Installs scan-repo and all prerequisite security scanning tools on:
#   - macOS (x86_64 and Apple Silicon)
#   - Linux: Ubuntu/Debian, RHEL/CentOS/Fedora/Rocky/Alma, Arch
#   - Windows via WSL (run this script inside a WSL terminal)
#
# Usage:
#   ./install.sh [OPTIONS]
#
# Options:
#   -y, --yes              Skip confirmation prompts
#   --prefix DIR           Binary install prefix (default: /usr/local/bin)
#   --skip-semgrep         Skip Semgrep (SAST)
#   --skip-trivy           Skip Trivy (dependency + IaC scanning)
#   --skip-osv             Skip OSV-Scanner (dependency scanning)
#   --skip-grype           Skip Grype (vulnerability scanning)
#   --skip-node            Skip Node.js and npm tools
#   --skip-scan-repo       Skip installing the scan-repo command itself
#   -h, --help             Show this help
###############################################################################

set -euo pipefail

###############################################################################
# Configuration
###############################################################################

INSTALL_PREFIX="/usr/local/bin"
ASSUME_YES=false
SKIP_SEMGREP=false
SKIP_TRIVY=false
SKIP_OSV=false
SKIP_GRYPE=false
SKIP_NODE=false
SKIP_JAVA=false
SKIP_SCAN_REPO=false

OS=""
ARCH=""
DISTRO=""
SUDO=""

###############################################################################
# Colors and logging
###############################################################################

if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; RESET=""
fi

log_info()    { echo "${BLUE}[INFO]${RESET}    $*"; }
log_ok()      { echo "${GREEN}[OK]${RESET}      $*"; }
log_warn()    { echo "${YELLOW}[WARN]${RESET}    $*"; }
log_error()   { echo "${RED}[ERROR]${RESET}   $*" >&2; }
log_section() { echo ""; echo "${CYAN}${BOLD}▶ $*${RESET}"; }
log_skip()    { echo "${YELLOW}[SKIP]${RESET}    $*"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

die() { log_error "$*"; exit 1; }

###############################################################################
# Argument parsing
###############################################################################

show_help() {
    cat <<EOF
${BOLD}scan-repo Installer${RESET}

Installs scan-repo and all prerequisite security scanning tools.

${BOLD}Usage:${RESET}
  ./install.sh [OPTIONS]

${BOLD}Options:${RESET}
  -y, --yes              Skip confirmation prompts
  --prefix DIR           Install binaries to DIR (default: /usr/local/bin)
  --skip-semgrep         Skip Semgrep SAST scanner
  --skip-trivy           Skip Trivy scanner
  --skip-osv             Skip OSV-Scanner
  --skip-grype           Skip Grype scanner
  --skip-node            Skip Node.js and npm tools (retire, license-checker)
  --skip-java            Skip OWASP Dependency-Check (Java SCA)
  --skip-scan-repo       Skip installing the scan-repo command itself
  -h, --help             Show this help

${BOLD}Examples:${RESET}
  ./install.sh                        # Full installation
  ./install.sh --yes                  # Non-interactive full installation
  ./install.sh --prefix ~/.local/bin  # Install to user directory (no sudo)
  ./install.sh --skip-node --yes      # Skip Node.js tools
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)          ASSUME_YES=true; shift ;;
            --prefix)          INSTALL_PREFIX="$2"; shift 2 ;;
            --skip-semgrep)    SKIP_SEMGREP=true; shift ;;
            --skip-trivy)      SKIP_TRIVY=true; shift ;;
            --skip-osv)        SKIP_OSV=true; shift ;;
            --skip-grype)      SKIP_GRYPE=true; shift ;;
            --skip-node)       SKIP_NODE=true; shift ;;
            --skip-java)       SKIP_JAVA=true; shift ;;
            --skip-scan-repo)  SKIP_SCAN_REPO=true; shift ;;
            -h|--help)         show_help; exit 0 ;;
            *) die "Unknown option: $1. Use --help for usage." ;;
        esac
    done
}

###############################################################################
# OS / arch detection
###############################################################################

detect_os() {
    log_section "Detecting environment"

    # Detect OS
    case "$(uname -s)" in
        Linux)
            OS="linux"
            # Detect WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                log_info "Running in WSL (Windows Subsystem for Linux)"
            fi
            # Detect distribution
            if [ -f /etc/os-release ]; then
                # shellcheck source=/dev/null
                . /etc/os-release
                DISTRO="${ID:-unknown}"
            else
                DISTRO="unknown"
            fi
            ;;
        Darwin)
            OS="macos"
            DISTRO="macos"
            ;;
        MINGW*|CYGWIN*|MSYS*)
            die "Detected Git Bash / Cygwin on Windows.
Please use WSL (Windows Subsystem for Linux) instead.
See README.md for Windows installation instructions."
            ;;
        *)
            die "Unsupported OS: $(uname -s)"
            ;;
    esac

    # Detect CPU architecture
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l)        ARCH="arm"   ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac

    log_ok "OS: ${OS} (${DISTRO}), Architecture: ${ARCH}"
}

###############################################################################
# Permission / sudo handling
###############################################################################

setup_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
        log_info "Running as root"
    elif command_exists sudo; then
        SUDO="sudo"
        # Warm up sudo credentials early so we don't prompt mid-install
        log_info "Requesting sudo access (required to install system packages)"
        sudo -v || die "sudo access required. Re-run as root or with sudo."
        # Keep sudo alive in the background
        ( while true; do sudo -n true; sleep 50; done ) &
        SUDO_KEEPALIVE_PID=$!
        trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
    else
        die "This script requires root or sudo access to install system packages."
    fi
}

###############################################################################
# Package manager helpers
###############################################################################

apt_install() {
    $SUDO apt-get install -y --no-install-recommends "$@"
}

brew_install() {
    # Install without prompting; suppress noisy caveats
    HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@" 2>&1 | grep -v "^==" || true
}

###############################################################################
# System prerequisites
###############################################################################

install_prerequisites() {
    log_section "Installing system prerequisites"

    case "$OS" in
        linux)
            case "$DISTRO" in
                ubuntu|debian|linuxmint|pop|elementary)
                    $SUDO apt-get update -qq 2>/dev/null || log_warn "apt-get update had warnings (possibly unrelated repos)"
                    apt_install curl wget jq unzip ca-certificates gnupg lsb-release python3 python3-pip
                    ;;
                rhel|centos|rocky|almalinux|ol)
                    $SUDO yum install -y curl wget jq unzip ca-certificates gnupg python3 python3-pip
                    ;;
                fedora)
                    $SUDO dnf install -y curl wget jq unzip ca-certificates gnupg python3 python3-pip
                    ;;
                arch|manjaro|endeavouros)
                    $SUDO pacman -Sy --noconfirm curl wget jq unzip ca-certificates gnupg python python-pip
                    ;;
                alpine)
                    $SUDO apk add --no-cache curl wget jq unzip ca-certificates gnupg python3 py3-pip
                    ;;
                *)
                    log_warn "Unknown Linux distribution '${DISTRO}'. Attempting generic install."
                    command_exists curl  || die "curl is required. Please install it manually."
                    command_exists jq    || die "jq is required. Please install it manually."
                    ;;
            esac
            ;;
        macos)
            if ! command_exists brew; then
                die "Homebrew is required on macOS.
Install it from https://brew.sh, then re-run this script."
            fi
            brew_install curl wget jq
            ;;
    esac

    log_ok "Prerequisites installed"
}

###############################################################################
# Node.js + npm
###############################################################################

install_node() {
    if [ "$SKIP_NODE" = true ]; then
        log_skip "Node.js (--skip-node)"; return
    fi

    log_section "Installing Node.js and npm tools"

    if ! command_exists node; then
        log_info "Installing Node.js 20 LTS..."
        case "$OS" in
            linux)
                case "$DISTRO" in
                    ubuntu|debian|linuxmint|pop|elementary)
                        curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash - 2>/dev/null
                        apt_install nodejs
                        ;;
                    rhel|centos|rocky|almalinux|ol)
                        curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO bash - 2>/dev/null
                        $SUDO yum install -y nodejs
                        ;;
                    fedora)
                        curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO bash - 2>/dev/null
                        $SUDO dnf install -y nodejs
                        ;;
                    arch|manjaro|endeavouros)
                        $SUDO pacman -Sy --noconfirm nodejs npm
                        ;;
                    alpine)
                        $SUDO apk add --no-cache nodejs npm
                        ;;
                    *)
                        log_warn "Cannot auto-install Node.js on ${DISTRO}."
                        log_warn "Install Node.js 20 LTS from https://nodejs.org and re-run."
                        return
                        ;;
                esac
                ;;
            macos)
                brew_install node@20
                # Ensure the formula's bin dir is on PATH
                NODE_PREFIX=$(brew --prefix node@20 2>/dev/null || true)
                [ -n "$NODE_PREFIX" ] && export PATH="${NODE_PREFIX}/bin:${PATH}"
                ;;
        esac
    else
        log_info "Node.js already installed: $(node --version)"
    fi

    if ! command_exists node; then
        log_warn "Node.js installation failed. Skipping npm tools."
        return
    fi

    log_ok "Node.js: $(node --version), npm: $(npm --version)"

    # Determine safe npm global prefix (avoid requiring sudo for npm -g)
    local npm_prefix
    npm_prefix=$(npm config get prefix 2>/dev/null || echo "")
    local npm_bin="${npm_prefix}/bin"

    # Install yarn (for yarn audit support)
    log_info "Installing yarn..."
    npm install -g yarn 2>/dev/null \
        && log_ok  "yarn installed" \
        || log_warn "yarn installation failed (optional)"

    # Install npm tools globally
    log_info "Installing retire.js..."
    npm install -g retire@latest 2>/dev/null \
        && log_ok  "retire.js installed" \
        || log_warn "retire.js installation failed (optional)"

    log_info "Installing license-checker..."
    npm install -g license-checker@latest 2>/dev/null \
        && log_ok  "license-checker installed" \
        || log_warn "license-checker installation failed (optional)"

    # Install pip-audit for Python dependency scanning
    log_info "Installing pip-audit..."
    if command_exists pip3; then
        pip3 install pip-audit --break-system-packages 2>/dev/null \
            || pip3 install pip-audit 2>/dev/null \
            && log_ok  "pip-audit installed" \
            || log_warn "pip-audit installation failed (optional, install manually: pip install pip-audit)"
    elif command_exists pip; then
        pip install pip-audit --break-system-packages 2>/dev/null \
            || pip install pip-audit 2>/dev/null \
            && log_ok  "pip-audit installed" \
            || log_warn "pip-audit installation failed (optional, install manually: pip install pip-audit)"
    else
        log_warn "pip/pip3 not found — skipping pip-audit (install manually: pip install pip-audit)"
    fi

    # Ensure npm global bin is on PATH
    if [[ ":$PATH:" != *":${npm_bin}:"* ]]; then
        export PATH="${npm_bin}:${PATH}"
    fi
}

###############################################################################
# Semgrep
###############################################################################

install_semgrep() {
    if [ "$SKIP_SEMGREP" = true ]; then
        log_skip "Semgrep (--skip-semgrep)"; return
    fi

    log_section "Installing Semgrep (SAST)"

    if command_exists semgrep; then
        log_ok "Semgrep already installed: $(semgrep --version 2>&1 | head -n1)"
        return
    fi

    case "$OS" in
        macos)
            brew_install semgrep
            ;;
        linux)
            local semgrep_arch
            case "$ARCH" in
                amd64) semgrep_arch="x86_64" ;;
                arm64) semgrep_arch="aarch64" ;;
                *)
                    log_warn "No Semgrep binary for ${ARCH}. Falling back to pip."
                    semgrep_arch=""
                    ;;
            esac

            if [ -n "$semgrep_arch" ]; then
                log_info "Downloading Semgrep binary..."
                local tmp; tmp=$(mktemp -d)
                local url="https://github.com/semgrep/semgrep/releases/latest/download/semgrep-linux-${semgrep_arch}.zip"
                curl -fsSL "$url" -o "${tmp}/semgrep.zip" \
                    || { log_warn "Binary download failed, falling back to pip."; semgrep_arch=""; }
                if [ -n "$semgrep_arch" ]; then
                    unzip -q "${tmp}/semgrep.zip" -d "${tmp}"
                    local bin; bin=$(find "$tmp" -name "semgrep" -type f | head -n1)
                    if [ -n "$bin" ]; then
                        $SUDO install -m 755 "$bin" "${INSTALL_PREFIX}/semgrep"
                        rm -rf "$tmp"
                    else
                        log_warn "Binary not found in archive, falling back to pip."
                        semgrep_arch=""
                        rm -rf "$tmp"
                    fi
                fi
            fi

            # Pip fallback (covers arm and archive-fail cases)
            if [ -z "$semgrep_arch" ] || ! command_exists semgrep; then
                log_info "Installing Semgrep via pip..."
                if python3 -m pip install semgrep 2>/dev/null; then
                    :
                elif python3 -m pip install --break-system-packages semgrep 2>/dev/null; then
                    :
                else
                    log_warn "Semgrep installation failed. Install manually: pip3 install semgrep"
                    return
                fi
            fi
            ;;
    esac

    if command_exists semgrep; then
        log_ok "Semgrep: $(semgrep --version 2>&1 | head -n1)"
    else
        log_warn "Semgrep not found in PATH after install. You may need to reload your shell."
    fi
}

###############################################################################
# Trivy
###############################################################################

install_trivy() {
    if [ "$SKIP_TRIVY" = true ]; then
        log_skip "Trivy (--skip-trivy)"; return
    fi

    log_section "Installing Trivy (vulnerability + IaC scanner)"

    if command_exists trivy; then
        log_ok "Trivy already installed: $(trivy --version 2>&1 | head -n1)"
        return
    fi

    case "$OS" in
        macos)
            brew_install trivy
            ;;
        linux)
            case "$DISTRO" in
                ubuntu|debian|linuxmint|pop|elementary)
                    # Official Trivy apt repository
                    $SUDO mkdir -p /etc/apt/keyrings
                    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
                        | $SUDO gpg --dearmor -o /etc/apt/keyrings/trivy.gpg
                    echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc 2>/dev/null || echo stable) main" \
                        | $SUDO tee /etc/apt/sources.list.d/trivy.list >/dev/null
                    $SUDO apt-get update -qq 2>/dev/null || log_warn "apt-get update had warnings"
                    apt_install trivy
                    ;;
                rhel|centos|rocky|almalinux|ol|fedora)
                    cat <<'REPO' | $SUDO tee /etc/yum.repos.d/trivy.repo >/dev/null
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
REPO
                    $SUDO yum install -y trivy 2>/dev/null \
                        || $SUDO dnf install -y trivy
                    ;;
                arch|manjaro|endeavouros)
                    # Available in AUR; use binary download as fallback
                    _install_trivy_binary
                    ;;
                *)
                    _install_trivy_binary
                    ;;
            esac
            ;;
    esac

    if command_exists trivy; then
        log_ok "Trivy: $(trivy --version 2>&1 | head -n1)"
    else
        log_warn "Trivy installation failed. See https://trivy.dev/latest/getting-started/installation/"
    fi
}

_install_trivy_binary() {
    log_info "Downloading Trivy binary..."
    local trivy_arch
    case "$ARCH" in
        amd64) trivy_arch="Linux-64bit" ;;
        arm64) trivy_arch="Linux-ARM64" ;;
        arm)   trivy_arch="Linux-ARM"   ;;
        *) log_warn "Unsupported arch for Trivy binary: $ARCH"; return ;;
    esac
    local url="https://github.com/aquasecurity/trivy/releases/latest/download/trivy_latest_${trivy_arch}.tar.gz"
    local tmp; tmp=$(mktemp -d)
    curl -fsSL "$url" -o "${tmp}/trivy.tar.gz" \
        && tar -xzf "${tmp}/trivy.tar.gz" -C "$tmp" \
        && $SUDO install -m 755 "${tmp}/trivy" "${INSTALL_PREFIX}/trivy"
    rm -rf "$tmp"
}

###############################################################################
# OSV-Scanner
###############################################################################

install_osv_scanner() {
    if [ "$SKIP_OSV" = true ]; then
        log_skip "OSV-Scanner (--skip-osv)"; return
    fi

    log_section "Installing OSV-Scanner"

    if command_exists osv-scanner; then
        log_ok "OSV-Scanner already installed"
        return
    fi

    local osv_os osv_arch
    case "$OS" in
        macos) osv_os="darwin" ;;
        linux) osv_os="linux"  ;;
    esac
    case "$ARCH" in
        amd64) osv_arch="amd64" ;;
        arm64) osv_arch="arm64" ;;
        *)
            log_warn "No OSV-Scanner binary for ${ARCH}. Skipping."
            return
            ;;
    esac

    log_info "Downloading OSV-Scanner binary..."
    local url="https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_${osv_os}_${osv_arch}"
    curl -fsSL "$url" -o /tmp/osv-scanner \
        || { log_warn "OSV-Scanner download failed."; return; }
    $SUDO install -m 755 /tmp/osv-scanner "${INSTALL_PREFIX}/osv-scanner"
    rm -f /tmp/osv-scanner

    if command_exists osv-scanner; then
        log_ok "OSV-Scanner installed"
    else
        log_warn "OSV-Scanner not found in PATH after install."
    fi
}

###############################################################################
# Grype
###############################################################################

install_grype() {
    if [ "$SKIP_GRYPE" = true ]; then
        log_skip "Grype (--skip-grype)"; return
    fi

    log_section "Installing Grype (vulnerability scanner)"

    if command_exists grype; then
        log_ok "Grype already installed: $(grype version 2>&1 | grep -i version | head -n1)"
        return
    fi

    case "$OS" in
        macos)
            brew_install grype
            ;;
        linux)
            log_info "Downloading Grype via official installer..."
            curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh \
                | $SUDO sh -s -- -b "${INSTALL_PREFIX}" 2>/dev/null \
                || { log_warn "Grype installer failed."; return; }
            ;;
    esac

    if command_exists grype; then
        log_ok "Grype: $(grype version 2>&1 | grep -i version | head -n1)"
    else
        log_warn "Grype installation failed. See https://github.com/anchore/grype"
    fi
}

###############################################################################
# OWASP Dependency-Check (Java SCA)
###############################################################################

install_dependency_check() {
    if [ "$SKIP_JAVA" = true ]; then
        log_skip "OWASP Dependency-Check (--skip-java)"; return
    fi

    log_section "Installing OWASP Dependency-Check (Java SCA)"

    # Requires Java 11+
    local java_ok=false
    if command_exists java; then
        local java_ver
        java_ver=$(java -version 2>&1 | grep -oP '(?<=version ")\d+' | head -n1 || true)
        # Java versioning: "1.8" = 8, "11" = 11, "17" = 17 etc.
        [ "$java_ver" = "1" ] && java_ver=$(java -version 2>&1 | grep -oP '(?<=version "1\.)\d+' | head -n1 || true)
        if [ -n "$java_ver" ] && [ "$java_ver" -ge 11 ] 2>/dev/null; then
            java_ok=true
        fi
    fi
    if [ "$java_ok" = false ]; then
        log_warn "Java 11+ not found — skipping OWASP Dependency-Check"
        log_warn "Install openjdk-11-jdk and re-run to enable Java dependency scanning"
        return
    fi

    if command_exists dependency-check; then
        log_ok "OWASP Dependency-Check already installed"
        return
    fi

    # Try GitHub API first; fall back to a pinned known-good version
    local version
    version=$(curl -s --max-time 10 "https://api.github.com/repos/jeremylong/DependencyCheck/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' | head -n1 || true)
    if [ -z "$version" ]; then
        version="12.1.0"   # last confirmed good release (11.x fails on NVD CVSS v4 SAFETY enum)
    fi

    local url="https://github.com/jeremylong/DependencyCheck/releases/download/v${version}/dependency-check-${version}-release.zip"
    local zip_file="/tmp/dependency-check-${version}.zip"
    local install_dir="/opt/dependency-check"

    log_info "Downloading OWASP Dependency-Check v${version}..."
    curl -fsSL "$url" -o "$zip_file" || {
        log_warn "Download failed. See https://github.com/jeremylong/DependencyCheck/releases"
        return
    }

    log_info "Extracting to ${install_dir}..."
    $SUDO mkdir -p /opt
    $SUDO unzip -q "$zip_file" -d /opt/
    $SUDO chmod +x "${install_dir}/bin/dependency-check.sh"

    # Symlink into the install prefix
    $SUDO ln -sf "${install_dir}/bin/dependency-check.sh" "${INSTALL_PREFIX}/dependency-check"

    rm -f "$zip_file"

    if command_exists dependency-check; then
        log_ok "OWASP Dependency-Check v${version} installed"
        log_info "Note: First scan will download the NVD database (~300 MB, ~15 min)"
    else
        log_warn "OWASP Dependency-Check installation may have failed"
    fi
}

###############################################################################
# scan-repo itself
###############################################################################

install_scan_repo() {
    if [ "$SKIP_SCAN_REPO" = true ]; then
        log_skip "scan-repo (--skip-scan-repo)"; return
    fi

    log_section "Installing scan-repo"

    # Find scan-repo: next to this install script, or in PATH already
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local scan_repo_src="${script_dir}/scan-repo"

    if [ ! -f "$scan_repo_src" ]; then
        log_warn "scan-repo not found next to install.sh (expected: ${scan_repo_src})"
        log_warn "Download scan-repo manually and copy it to ${INSTALL_PREFIX}/scan-repo"
        return
    fi

    $SUDO install -m 755 "$scan_repo_src" "${INSTALL_PREFIX}/scan-repo"

    if command_exists scan-repo; then
        log_ok "scan-repo installed to ${INSTALL_PREFIX}/scan-repo"
    else
        log_warn "scan-repo installed but not found in PATH. Ensure ${INSTALL_PREFIX} is in your PATH."
    fi
}

###############################################################################
# Verification
###############################################################################

verify_installations() {
    log_section "Verification"
    echo ""

    local tools=(
        "scan-repo:scan-repo"
        "semgrep:Semgrep (SAST)"
        "trivy:Trivy (vuln + IaC)"
        "osv-scanner:OSV-Scanner"
        "grype:Grype"
        "node:Node.js"
        "npm:npm"
        "retire:retire.js"
        "license-checker:license-checker"
        "pip-audit:pip-audit (Python dep scanner)"
        "dependency-check:OWASP Dependency-Check (Java)"
        "yarn:yarn (optional, for yarn audit)"
        "jq:jq (JSON processor)"
    )

    local pass=0 fail=0
    for pair in "${tools[@]}"; do
        local cmd="${pair%%:*}"
        local name="${pair#*:}"
        if command_exists "$cmd"; then
            echo "  ${GREEN}✓${RESET} $name"
            (( pass++ )) || true
        else
            echo "  ${RED}✗${RESET} $name"
            (( fail++ )) || true
        fi
    done

    echo ""
    log_info "Installed: ${pass} / $((pass + fail)) tools"

    local core_missing=0
    for cmd in semgrep trivy osv-scanner grype; do
        command_exists "$cmd" || (( core_missing++ )) || true
    done

    if [ "$core_missing" -eq 0 ]; then
        log_ok "All core scanning tools are ready."
    else
        log_warn "${core_missing} core tool(s) failed to install."
        log_warn "You can skip individual tools with --skip-<tool> and re-run later."
    fi
}

###############################################################################
# Shell config (PATH helpers for the user's rc files)
###############################################################################

update_shell_path() {
    # Only needed when INSTALL_PREFIX is not already on PATH
    if [[ ":$PATH:" == *":${INSTALL_PREFIX}:"* ]]; then
        return
    fi

    local rc_file
    case "${SHELL:-}" in
        */zsh)  rc_file="${HOME}/.zshrc"  ;;
        */fish) rc_file="${HOME}/.config/fish/config.fish" ;;
        *)      rc_file="${HOME}/.bashrc" ;;
    esac

    if [ -f "$rc_file" ] && ! grep -q "${INSTALL_PREFIX}" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# Added by scan-repo installer" >> "$rc_file"
        echo "export PATH=\"${INSTALL_PREFIX}:\$PATH\"" >> "$rc_file"
        log_info "Added ${INSTALL_PREFIX} to PATH in ${rc_file}"
        log_info "Run: source ${rc_file}  (or open a new terminal)"
    fi
}

###############################################################################
# Main
###############################################################################

print_banner() {
    echo ""
    echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}║         scan-repo  ·  Security Tools Installer            ║${RESET}"
    echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_plan() {
    echo "The following will be installed to ${BOLD}${INSTALL_PREFIX}${RESET}:"
    echo ""
    [ "$SKIP_SEMGREP"    = false ] && echo "  • Semgrep        — SAST (code vulnerabilities & secrets)"
    [ "$SKIP_TRIVY"      = false ] && echo "  • Trivy          — SCA + IaC misconfiguration scanner"
    [ "$SKIP_OSV"        = false ] && echo "  • OSV-Scanner    — dependency vulnerability database"
    [ "$SKIP_GRYPE"      = false ] && echo "  • Grype          — container + filesystem vulnerability scanner"
    [ "$SKIP_NODE"       = false ] && echo "  • Node.js / npm  — runtime for retire.js, yarn, and license-checker"
    [ "$SKIP_NODE"       = false ] && echo "  • yarn           — yarn audit for yarn.lock projects"
    [ "$SKIP_NODE"       = false ] && echo "  • pip-audit      — Python dependency vulnerability scanner"
    [ "$SKIP_JAVA"       = false ] && echo "  • OWASP DC       — Java SCA (pom.xml, Gradle, JARs, WARs)"
    [ "$SKIP_SCAN_REPO"  = false ] && echo "  • scan-repo      — the main scanner command"
    echo ""
}

main() {
    parse_args "$@"
    print_banner
    detect_os
    print_plan

    if [ "$ASSUME_YES" = false ]; then
        read -r -p "Continue with installation? [y/N] " reply
        echo ""
        [[ "$reply" =~ ^[Yy]$ ]] || { log_info "Installation cancelled."; exit 0; }
    fi

    setup_sudo

    install_prerequisites
    install_node
    install_semgrep
    install_trivy
    install_osv_scanner
    install_grype
    install_dependency_check
    install_scan_repo
    update_shell_path

    verify_installations

    echo ""
    echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
    echo "${GREEN}${BOLD}  Installation complete!${RESET}"
    echo "${GREEN}${BOLD}════════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo "  Quick start:"
    echo "    cd /path/to/your/repo"
    echo "    scan-repo --markdown"
    echo ""
    echo "  Run with all report formats:"
    echo "    scan-repo --all-formats -o ./reports ."
    echo ""
    echo "  See all options:"
    echo "    scan-repo --help"
    echo ""
}

main "$@"
