#!/usr/bin/env bash
# setup_server.sh
# Sets up a fresh server with all dependencies for the AI video dubbing pipeline.
#
# Usage:
#   sudo ./setup_server.sh
#
# Installs: ffmpeg, yt-dlp, python3+pip, Kokoro TTS, n8n, and creates directories.
# Tested on: Ubuntu 22.04/24.04, Debian 12

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
PROJECT_DIR="${PROJECT_DIR:-/opt/ai_video_dubbing}"
N8N_DATA_DIR="${N8N_DATA_DIR:-/opt/n8n_data}"
VENV_DIR="${PROJECT_DIR}/venv"
NODE_VERSION="20"
LOG_FILE="/tmp/setup_server_$(date +%Y%m%d_%H%M%S).log"

# ── Logging ──────────────────────────────────────────────────────────────────
exec > >(tee -a "$LOG_FILE") 2>&1

log()     { echo "[setup] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
success() { echo "[setup] OK: $*"; }
warn()    { echo "[setup] WARNING: $*"; }
err()     { echo "[setup] ERROR: $*" >&2; }
die()     { err "$@"; exit 1; }

separator() { echo ""; echo "================================================================"; echo "  $*"; echo "================================================================"; echo ""; }

# ── Pre-flight checks ───────────────────────────────────────────────────────
separator "Pre-flight checks"

if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root (use sudo)"
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_NAME="$ID"
    OS_VERSION="$VERSION_ID"
    log "Detected OS: $PRETTY_NAME"
else
    warn "Cannot detect OS. Assuming Debian-based."
    OS_NAME="debian"
    OS_VERSION="unknown"
fi

if [[ "$OS_NAME" != "ubuntu" ]] && [[ "$OS_NAME" != "debian" ]]; then
    warn "This script is designed for Ubuntu/Debian. Other distros may need adjustments."
fi

log "Log file: $LOG_FILE"
log "Project directory: $PROJECT_DIR"

# ── System update ────────────────────────────────────────────────────────────
separator "Updating system packages"

apt-get update -y
apt-get upgrade -y
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    jq \
    bc \
    unzip

success "System packages updated"

# ── ffmpeg ───────────────────────────────────────────────────────────────────
separator "Installing ffmpeg"

if command -v ffmpeg &>/dev/null; then
    CURRENT_FFMPEG=$(ffmpeg -version 2>/dev/null | head -1)
    log "ffmpeg already installed: $CURRENT_FFMPEG"
else
    apt-get install -y ffmpeg
fi

# Verify
ffmpeg -version | head -1
ffprobe -version | head -1
success "ffmpeg installed"

# ── Python 3 + pip ───────────────────────────────────────────────────────────
separator "Installing Python 3 and pip"

apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev

PYTHON_VERSION=$(python3 --version)
log "$PYTHON_VERSION"
success "Python 3 installed"

# ── yt-dlp ───────────────────────────────────────────────────────────────────
separator "Installing yt-dlp"

# Install latest yt-dlp binary (pip version often lags behind)
if command -v yt-dlp &>/dev/null; then
    log "yt-dlp already installed: $(yt-dlp --version)"
    log "Updating to latest..."
fi

# Download latest release binary
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -o /usr/local/bin/yt-dlp
chmod a+rx /usr/local/bin/yt-dlp

yt-dlp --version
success "yt-dlp installed"

# ── Node.js (for n8n) ───────────────────────────────────────────────────────
separator "Installing Node.js ${NODE_VERSION}.x"

if command -v node &>/dev/null; then
    CURRENT_NODE=$(node --version)
    log "Node.js already installed: $CURRENT_NODE"
else
    # Use NodeSource repository
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
    apt-get install -y nodejs
fi

node --version
npm --version
success "Node.js installed"

# ── n8n ──────────────────────────────────────────────────────────────────────
separator "Installing n8n"

if command -v n8n &>/dev/null; then
    log "n8n already installed: $(n8n --version 2>/dev/null || echo 'version unknown')"
    log "Updating..."
fi

npm install -g n8n

mkdir -p "$N8N_DATA_DIR"

# Create systemd service for n8n
cat > /etc/systemd/system/n8n.service << 'UNIT'
[Unit]
Description=n8n workflow automation
After=network.target

[Service]
Type=simple
User=root
Environment=N8N_USER_FOLDER=/opt/n8n_data
Environment=N8N_PORT=5678
Environment=N8N_PROTOCOL=http
Environment=GENERIC_TIMEZONE=UTC
ExecStart=/usr/bin/env n8n start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable n8n

log "n8n service created (not started yet)"
success "n8n installed"

# ── Python virtual environment + dubbing dependencies ────────────────────────
separator "Setting up Python virtual environment"

mkdir -p "$PROJECT_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

pip install --upgrade pip setuptools wheel

# Core dependencies for the dubbing pipeline
pip install \
    openai-whisper \
    torch \
    torchaudio \
    numpy \
    scipy \
    requests \
    pydub \
    srt

success "Python venv created at $VENV_DIR"

# ── Kokoro TTS ───────────────────────────────────────────────────────────────
separator "Installing Kokoro TTS"

# Kokoro TTS is a lightweight TTS engine. Install from pip if available.
log "Attempting to install Kokoro TTS..."

KOKORO_INSTALLED=false

# Try pip install first (kokoro or kokoro-tts package)
if pip install kokoro 2>/dev/null; then
    KOKORO_INSTALLED=true
    success "Kokoro TTS installed via pip (kokoro)"
elif pip install kokoro-tts 2>/dev/null; then
    KOKORO_INSTALLED=true
    success "Kokoro TTS installed via pip (kokoro-tts)"
else
    warn "Kokoro TTS pip package not found. Trying git clone..."

    # Try cloning the repository
    KOKORO_DIR="${PROJECT_DIR}/kokoro-tts"
    if [[ -d "$KOKORO_DIR" ]]; then
        log "Kokoro directory already exists, pulling latest..."
        git -C "$KOKORO_DIR" pull || true
    else
        # Try common GitHub locations
        if git clone https://github.com/hexgrad/kokoro.git "$KOKORO_DIR" 2>/dev/null; then
            log "Cloned Kokoro from hexgrad/kokoro"
        elif git clone https://github.com/kokoro-tts/kokoro.git "$KOKORO_DIR" 2>/dev/null; then
            log "Cloned Kokoro from kokoro-tts/kokoro"
        else
            warn "Could not clone Kokoro TTS repository"
        fi
    fi

    if [[ -d "$KOKORO_DIR" ]]; then
        if [[ -f "$KOKORO_DIR/setup.py" ]] || [[ -f "$KOKORO_DIR/pyproject.toml" ]]; then
            pip install -e "$KOKORO_DIR" 2>/dev/null && KOKORO_INSTALLED=true
        elif [[ -f "$KOKORO_DIR/requirements.txt" ]]; then
            pip install -r "$KOKORO_DIR/requirements.txt" 2>/dev/null && KOKORO_INSTALLED=true
        fi
    fi
fi

if $KOKORO_INSTALLED; then
    success "Kokoro TTS installed"
else
    warn "Kokoro TTS could not be installed automatically."
    warn "You may need to install it manually. The pipeline can fall back to other TTS engines."
    echo "  Manual install options:" >> "$LOG_FILE"
    echo "    pip install kokoro" >> "$LOG_FILE"
    echo "    or clone and install from the project's GitHub repository" >> "$LOG_FILE"
fi

deactivate

# ── Create project directories ──────────────────────────────────────────────
separator "Creating project directories"

DIRS=(
    "$PROJECT_DIR/downloads"
    "$PROJECT_DIR/temp"
    "$PROJECT_DIR/temp/audio_segments"
    "$PROJECT_DIR/temp/transcriptions"
    "$PROJECT_DIR/temp/translations"
    "$PROJECT_DIR/output"
    "$PROJECT_DIR/output/dubbed"
    "$PROJECT_DIR/output/clips"
    "$PROJECT_DIR/scripts"
    "$PROJECT_DIR/models"
    "$PROJECT_DIR/logs"
    "$N8N_DATA_DIR"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
    log "  Created: $dir"
done

success "Directories created"

# ── Copy scripts to project directory ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR" ]] && [[ "$SCRIPT_DIR" != "$PROJECT_DIR/scripts" ]]; then
    log "Copying n8n scripts to $PROJECT_DIR/scripts/"
    cp -v "$SCRIPT_DIR"/*.sh "$PROJECT_DIR/scripts/" 2>/dev/null || true
    cp -v "$SCRIPT_DIR"/*.js "$PROJECT_DIR/scripts/" 2>/dev/null || true
    chmod +x "$PROJECT_DIR/scripts/"*.sh 2>/dev/null || true
fi

# ── Verification ─────────────────────────────────────────────────────────────
separator "Verifying installations"

PASS=0
FAIL=0

check_tool() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        local version
        version=$(eval "$cmd" 2>&1 | head -1)
        echo "  [PASS] $name: $version"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $name: not found or not working"
        FAIL=$((FAIL + 1))
    fi
}

check_tool "ffmpeg"   "ffmpeg -version"
check_tool "ffprobe"  "ffprobe -version"
check_tool "yt-dlp"   "yt-dlp --version"
check_tool "python3"  "python3 --version"
check_tool "pip"      "$VENV_DIR/bin/pip --version"
check_tool "node"     "node --version"
check_tool "npm"      "npm --version"
check_tool "n8n"      "n8n --version"
check_tool "git"      "git --version"
check_tool "jq"       "jq --version"
check_tool "bc"       "echo '1+1' | bc"

echo ""

# Test ffmpeg can encode
log "Testing ffmpeg encoding..."
TEST_FILE="/tmp/ffmpeg_test_$$.mp4"
if ffmpeg -y -f lavfi -i testsrc=duration=1:size=320x240:rate=1 \
    -f lavfi -i sine=frequency=440:duration=1 \
    -c:v libx264 -c:a aac -shortest "$TEST_FILE" 2>/dev/null; then
    echo "  [PASS] ffmpeg encoding test"
    PASS=$((PASS + 1))
    rm -f "$TEST_FILE"
else
    echo "  [FAIL] ffmpeg encoding test"
    FAIL=$((FAIL + 1))
fi

# Test Python venv and whisper
log "Testing Python environment..."
if "$VENV_DIR/bin/python" -c "import whisper; print(f'  [PASS] whisper {whisper.__version__}')" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    echo "  [FAIL] whisper import"
    FAIL=$((FAIL + 1))
fi

echo ""
separator "Setup Complete"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
echo "  Project directory: $PROJECT_DIR"
echo "  Python venv:       $VENV_DIR"
echo "  n8n data:          $N8N_DATA_DIR"
echo "  Log file:          $LOG_FILE"
echo ""
echo "  Next steps:"
echo "    1. Start n8n:     sudo systemctl start n8n"
echo "    2. Access n8n:    http://<server-ip>:5678"
echo "    3. Activate venv: source $VENV_DIR/bin/activate"
echo ""

if [[ $FAIL -gt 0 ]]; then
    warn "$FAIL checks failed. Review the log at $LOG_FILE"
    exit 1
fi

success "All checks passed. Server is ready."
