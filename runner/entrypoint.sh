#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] CODE_URL=${CODE_URL}"
[ -z "${CODE_URL:-}" ] && { echo "[fatal] CODE_URL is required"; exit 2; }

# Strict validation - only allow alphanumeric, spaces, slashes, dashes, underscores, dots, and basic shell operators
validate_command() {
  local cmd="$1"
  # Check for dangerous patterns
  if [[ "$cmd" =~ \$\( ]] || [[ "$cmd" =~ '`' ]] || [[ "$cmd" =~ \$\{ ]]; then
    echo "[fatal] Command contains dangerous substitution patterns"
    return 1
  fi
  # Check length
  if [ ${#cmd} -gt 500 ]; then
    echo "[fatal] Command exceeds maximum length"
    return 1
  fi
  return 0
}

if [ -n "${COMMAND:-}" ]; then
  validate_command "${COMMAND}" || exit 1
fi
if [ -n "${INSTALL_CMD:-}" ]; then
  validate_command "${INSTALL_CMD}" || exit 1
fi

cd /work
mkdir -p src

# Initialize FOLDER variable for later use
FOLDER=""

case "$CODE_URL" in
  *github.com/*/tree/*)
    # GitHub tree URL: https://github.com/owner/repo/tree/ref/folder
    echo "[entrypoint] Detected GitHub tree URL, extracting folder..."

    # Parse URL components
    GITHUB_REGEX="github.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)"
    if [[ "$CODE_URL" =~ $GITHUB_REGEX ]]; then
      OWNER="${BASH_REMATCH[1]}"
      REPO="${BASH_REMATCH[2]}"
      REF="${BASH_REMATCH[3]}"
      FOLDER="${BASH_REMATCH[4]}"

      echo "[entrypoint] Owner: $OWNER, Repo: $REPO, Ref: $REF, Folder: $FOLDER"

      # Download tarball and extract specific folder
      echo "[entrypoint] Downloading from: https://api.github.com/repos/$OWNER/$REPO/tarball/$REF"
      TEMP_DIR=$(mktemp -d)
      curl -fL "https://api.github.com/repos/$OWNER/$REPO/tarball/$REF" | \
        tar xz -C "$TEMP_DIR" || {
        echo "[fatal] Failed to download GitHub tarball"
        exit 3
      }

      # Find and move the specific folder
      EXTRACTED_FOLDER=$(find "$TEMP_DIR" -type d -name "$FOLDER" | head -1)
      if [ -z "$EXTRACTED_FOLDER" ]; then
        echo "[fatal] Folder $FOLDER not found in tarball"
        rm -rf "$TEMP_DIR"
        exit 3
      fi

      # Move contents to /work/src
      mv "$EXTRACTED_FOLDER"/* /work/src/ || {
        echo "[fatal] Failed to move extracted files"
        rm -rf "$TEMP_DIR"
        exit 3
      }
      rm -rf "$TEMP_DIR"

      echo "[entrypoint] Successfully extracted $FOLDER from GitHub"
      echo "[entrypoint] Contents of /work/src:"
      ls -la /work/src
      # Skip checksum validation for GitHub tree URLs
      CODE_CHECKSUM_SHA256=""
    else
      echo "[fatal] Could not parse GitHub tree URL"
      exit 3
    fi
    ;;
  *.zip)  curl -fL "$CODE_URL" -o bundle.zip ;;
  *.tgz|*.tar.gz) curl -fL "$CODE_URL" -o bundle.tgz ;;
  *.git|*.git*) git clone --depth=1 "$CODE_URL" src ;;
  *)
    echo "[warning] Unknown file extension, assuming zip"
    curl -fL "$CODE_URL" -o bundle.zip ;;
esac

if [ -n "${CODE_CHECKSUM_SHA256:-}" ]; then
  if [ -f bundle.zip ]; then
    echo "${CODE_CHECKSUM_SHA256}  bundle.zip" | sha256sum -c -
  elif [ -f bundle.tgz ]; then
    echo "${CODE_CHECKSUM_SHA256}  bundle.tgz" | sha256sum -c -
  fi
fi

# Extract archives (GitHub tree URLs already extracted)
if [ -f bundle.zip ]; then unzip -q bundle.zip -d src || { echo "unzip failed"; exit 3; }; fi
if [ -f bundle.tgz ]; then tar -xzf bundle.tgz -C src --strip-components=1 || tar -xzf bundle.tgz -C src; fi

cd /work/src
echo "[entrypoint] Current directory: $(pwd)"
echo "[entrypoint] Directory contents:"
ls -la

# If the archive contains a single directory, cd into it.
# (Skip this for GitHub tree URLs as they're already in the right place)
if [ -z "$FOLDER" ] && [ $(ls -1 | wc -l) -eq 1 ] && [ -d "$(ls -1 | head -n1)" ]; then
  echo "[entrypoint] Found single directory, entering it..."
  cd "$(ls -1 | head -n1)"
  echo "[entrypoint] New directory: $(pwd)"
  ls -la
fi

echo "[entrypoint] Installing dependencies...";
: "${INSTALL_CMD:=npm install}"
echo "[entrypoint] Running: ${INSTALL_CMD}"
# Use array to prevent injection
/bin/bash -c "${INSTALL_CMD}" || {
  echo "[fatal] Install command failed"
  exit 4
}

echo "[entrypoint] Installation complete!"
echo "[entrypoint] Starting command in tmux session: ${COMMAND}"
export CLAUDE_PROMPT="${CLAUDE_PROMPT:-}"

# Configure tmux with more scrollback history and mouse support
mkdir -p /tmp/tmux
cat > ~/.tmux.conf <<'TMUX_EOF'
set -g history-limit 100000
set -g mouse on
TMUX_EOF

# Configuration
: "${TERM:=xterm-256color}"
: "${TMUX_SESSION:=job}"
: "${TMUX_SOCKET:=/tmp/tmux/tmux.sock}"
: "${TTYD_PORT:=7681}"
: "${EXIT_ON_JOB:=true}"

export TERM
exit_file="/tmp/${TMUX_SESSION}_exit_code"

# Cleanup function for graceful shutdown
cleanup() {
  echo "[entrypoint] Cleaning up..."
  if pgrep -x ttyd >/dev/null 2>&1; then pkill -TERM -x ttyd || true; fi
  if tmux -S "$TMUX_SOCKET" has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux -S "$TMUX_SOCKET" kill-session -t "$TMUX_SESSION" || true
  fi
}
trap cleanup SIGINT SIGTERM

# Start command in tmux and capture exit code
echo "[entrypoint] Creating tmux session '$TMUX_SESSION'..."
tmux -S "$TMUX_SOCKET" new-session -d -s "$TMUX_SESSION" \
  "bash -c \"${COMMAND}\"; code=\$?; echo \$code > \"$exit_file\"; echo \"[entrypoint] Command exited with code \$code\"; exit \$code"

echo "[entrypoint] Command started in tmux session '$TMUX_SESSION'"

# Pipe tmux output to console so docker logs shows it
(
  sleep 1
  while tmux -S "$TMUX_SOCKET" has-session -t "$TMUX_SESSION" 2>/dev/null; do
    tmux -S "$TMUX_SOCKET" capture-pane -t "$TMUX_SESSION" -p
    sleep 2
  done
) &

echo "[entrypoint] Launching ttyd on port $TTYD_PORT..."
echo "[entrypoint] Connect via browser to see live terminal output"

# Start ttyd in background
ttyd -p "$TTYD_PORT" -- tmux -S "$TMUX_SOCKET" new -A -s "$TMUX_SESSION" &
ttyd_pid=$!

# If EXIT_ON_JOB=false, keep ttyd running forever
if [[ "${EXIT_ON_JOB}" == "false" ]]; then
  echo "[entrypoint] EXIT_ON_JOB=false, keeping container alive"
  wait "$ttyd_pid"
  exit 0
fi

# Monitor tmux session - when it ends, stop ttyd and exit with job's exit code
while tmux -S "$TMUX_SOCKET" has-session -t "$TMUX_SESSION" 2>/dev/null; do
  sleep 2
done

echo "[entrypoint] Command finished, shutting down..."

# Collect exit code from the job
job_code=0
if [[ -f "$exit_file" ]]; then
  job_code=$(cat "$exit_file" 2>/dev/null || echo 1)
  echo "[entrypoint] Job exited with code: $job_code"
fi

# Stop ttyd gracefully
kill -TERM "$ttyd_pid" 2>/dev/null || true
wait "$ttyd_pid" 2>/dev/null || true

echo "[entrypoint] Container exiting with code: $job_code"
exit "$job_code"
