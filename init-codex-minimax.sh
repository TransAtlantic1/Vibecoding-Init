#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Early env load to pick up VIBECODING_DATA_ROOT for default paths
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a; set +u; . "${SCRIPT_DIR}/.env"; set -u; set +a
fi

WORKSPACE_ROOT="${VIBECODING_DATA_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"

SCRIPT_NAME="init-codex-minimax.sh"
LOG_TAG="init-codex-minimax"
BEGIN_MARKER="# >>> codex-minimax init >>>"
END_MARKER="# <<< codex-minimax init <<<"

DEFAULT_BASE_URL="https://api.minimaxi.com/v1"
DEFAULT_API_KEY=""
DEFAULT_CODEX_HOME_ROOT="${WORKSPACE_ROOT}/.codex_home_minimax"
DEFAULT_ALIAS="codex-minimax"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_ENV_KEY_NAME="MINIMAX_API_KEY"
DEFAULT_H1_PROXY_ENABLED="true"
DEFAULT_H1_PROXY_PORT="8788"
DEFAULT_H1_PROXY_CONF="/etc/nginx/conf.d/codex_h1_proxy_minimax.conf"

BASE_URL="${DEFAULT_BASE_URL}"
API_KEY="${DEFAULT_API_KEY}"
CODEX_HOME_ROOT="${DEFAULT_CODEX_HOME_ROOT}"
ALIAS_NAME="${DEFAULT_ALIAS}"
ENV_FILE="${DEFAULT_ENV_FILE}"
ENV_KEY_NAME="${DEFAULT_ENV_KEY_NAME}"
H1_PROXY_ENABLED="${DEFAULT_H1_PROXY_ENABLED}"
H1_PROXY_PORT="${DEFAULT_H1_PROXY_PORT}"
H1_PROXY_CONF="${DEFAULT_H1_PROXY_CONF}"
SELF_TEST_ENABLED="false"

_ALIAS_FROM_CLI=""

BASE_SCHEME=""
BASE_HOSTPORT=""
BASE_PATH=""
EFFECTIVE_BASE_URL=""
HOST_OR_CONTAINER=""
VENV_NAME=""
FINAL_CODEX_HOME=""
PROFILE_FILE=""
CONFIG_PATH=""

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [options]

Options:
  --api-key <key>          API key (optional, defaults to ${ENV_KEY_NAME} in ${ENV_FILE}).
  --base-url <url>         Provider base URL (default: ${DEFAULT_BASE_URL}).
  --codex-home-root <dir>  Root dir for CODEX_HOME (default: \$HOME/fj/.codex_home_minimax).
  --alias <name>           Shell function name (default: ${DEFAULT_ALIAS}).
  --env-file <path>        Shared .env file (default: ${DEFAULT_ENV_FILE}).
  --enable-h1-proxy        Setup local nginx proxy and force upstream HTTP/1.1 (default).
  --disable-h1-proxy       Skip nginx proxy setup and use --base-url directly.
  --proxy-port <port>      Local proxy listen port (default: ${DEFAULT_H1_PROXY_PORT}).
  --check-connectivity     Run a Codex CLI smoke test after setup.
  -h, --help               Show this help message.
EOF
}

log() {
  printf '[%s] %s\n' "${LOG_TAG}" "$*"
}

warn() {
  printf '[%s][WARN] %s\n' "${LOG_TAG}" "$*" >&2
}

die() {
  printf '[%s][ERROR] %s\n' "${LOG_TAG}" "$*" >&2
  exit 1
}

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "Need root privileges for nginx setup. Re-run as root or install sudo."
  fi
}

load_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    return
  fi

  set -a
  set +u
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set -u
  set +a
}

resolve_api_key_from_env() {
  local resolved=""

  if [[ -n "$API_KEY" ]]; then
    return
  fi

  if [[ -n "$ENV_KEY_NAME" ]]; then
    resolved="${!ENV_KEY_NAME:-}"
  fi

  API_KEY="${resolved}"
}

sanitize_component() {
  local input="$1"
  local sanitized
  sanitized="$(printf '%s' "$input" | tr -cs '[:alnum:]._-' '_' | sed 's/^_*//; s/_*$//')"
  if [[ -z "$sanitized" ]]; then
    sanitized="unknown"
  fi
  printf '%s' "$sanitized"
}

detect_host_or_container() {
  local raw=""

  if [[ -n "${CONTAINER_NAME:-}" ]]; then
    raw="${CONTAINER_NAME}"
  elif [[ -n "${HOSTNAME:-}" ]]; then
    raw="${HOSTNAME}"
  elif [[ -f /etc/hostname ]]; then
    raw="$(cat /etc/hostname 2>/dev/null || true)"
  elif command -v hostname >/dev/null 2>&1; then
    raw="$(hostname 2>/dev/null || true)"
  fi

  if [[ -z "$raw" ]]; then
    raw="host"
  fi

  sanitize_component "$raw"
}

detect_venv_name() {
  local raw=""
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    raw="$(basename "$VIRTUAL_ENV")"
  elif [[ -n "${CONDA_DEFAULT_ENV:-}" ]]; then
    raw="${CONDA_DEFAULT_ENV}"
  else
    raw="system"
  fi
  sanitize_component "$raw"
}

detect_profile_file() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"

  case "$shell_name" in
    zsh)
      printf '%s/.zshrc' "$HOME"
      ;;
    bash)
      printf '%s/.bashrc' "$HOME"
      ;;
    *)
      if [[ -f "${HOME}/.bashrc" ]]; then
        printf '%s/.bashrc' "$HOME"
      elif [[ -f "${HOME}/.zshrc" ]]; then
        printf '%s/.zshrc' "$HOME"
      else
        printf '%s/.bashrc' "$HOME"
      fi
      ;;
  esac
}

escape_single_quotes() {
  local val="$1"
  printf "%s" "$val" | sed "s/'/'\\\\''/g"
}

parse_base_url() {
  local url="$1"
  local extracted

  extracted="$(printf '%s' "$url" | sed -nE 's#^(https?)://([^/]+)(/.*)?$#\1 \2 \3#p')"
  [[ -n "$extracted" ]] || die "Invalid --base-url: ${url}. Expected format like https://host/v1"

  BASE_SCHEME="$(printf '%s' "$extracted" | awk '{print $1}')"
  BASE_HOSTPORT="$(printf '%s' "$extracted" | awk '{print $2}')"
  BASE_PATH="$(printf '%s' "$extracted" | awk '{print $3}')"
  if [[ -z "$BASE_PATH" || "$BASE_PATH" == " " ]]; then
    BASE_PATH="/"
  fi
}

effective_base_url_from_proxy() {
  local trimmed_path
  trimmed_path="${BASE_PATH%/}"
  if [[ -z "$trimmed_path" ]]; then
    printf 'http://127.0.0.1:%s' "$H1_PROXY_PORT"
  else
    printf 'http://127.0.0.1:%s%s' "$H1_PROXY_PORT" "$trimmed_path"
  fi
}

ensure_nginx_installed() {
  if command -v nginx >/dev/null 2>&1; then
    return
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    die "nginx not found and apt-get unavailable. Install nginx manually, then rerun."
  fi

  log "nginx not found; installing via apt-get..."
  run_privileged apt-get update
  run_privileged apt-get install -y nginx
}

setup_h1_proxy() {
  local conf_tmp

  ensure_nginx_installed
  conf_tmp="$(mktemp)"

  cat >"$conf_tmp" <<EOF
server {
    listen 127.0.0.1:${H1_PROXY_PORT};
    server_name localhost;
    client_max_body_size 50M;

    location / {
        proxy_pass ${BASE_SCHEME}://${BASE_HOSTPORT};
        proxy_http_version 1.1;
        proxy_set_header Host ${BASE_HOSTPORT};
        proxy_set_header Connection "";
        proxy_ssl_server_name on;

        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
        proxy_socket_keepalive on;
        keepalive_timeout 3600s;
    }
}
EOF

  run_privileged mkdir -p "$(dirname "$H1_PROXY_CONF")"
  run_privileged cp "$conf_tmp" "$H1_PROXY_CONF"
  rm -f "$conf_tmp"

  run_privileged nginx -t
  if command -v systemctl >/dev/null 2>&1; then
    run_privileged systemctl reload nginx 2>/dev/null \
      || run_privileged systemctl restart nginx 2>/dev/null \
      || run_privileged nginx -s reload 2>/dev/null \
      || run_privileged nginx
  else
    run_privileged nginx -s reload 2>/dev/null || run_privileged nginx
  fi

  log "HTTP/1.1 proxy is ready at http://127.0.0.1:${H1_PROXY_PORT}"
}

upsert_profile_block() {
  local profile_file="$1"
  local codex_home="$2"
  local env_file="$3"
  local env_key_name="$4"
  local alias_name="$5"
  local tmp_file
  local escaped_home
  local escaped_env_file

  escaped_home="$(escape_single_quotes "$codex_home")"
  escaped_env_file="$(escape_single_quotes "$env_file")"
  tmp_file="$(mktemp)"

  touch "$profile_file"

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$profile_file" >"$tmp_file"

  {
    cat "$tmp_file"
    printf '\n%s\n' "$BEGIN_MARKER"
    printf "export CODEX_MINIMAX_HOME='%s'\n" "$escaped_home"
    printf "export CODEX_MINIMAX_ENV_FILE='%s'\n" "$escaped_env_file"
    printf "%s() (\n" "$alias_name"
    printf "  # 清理 OpenAI 相关环境变量，以免影响 MiniMax API 正常使用\n"
    printf "  unset OPENAI_API_KEY\n"
    printf "  unset OPENAI_BASE_URL\n"
    printf "  export CODEX_HOME='%s'\n" "$escaped_home"
    printf "  if [[ -f '%s' ]]; then\n" "$escaped_env_file"
    printf "    set -a\n"
    printf "    source '%s'\n" "$escaped_env_file"
    printf "    set +a\n"
    printf "  fi\n"
    printf "  export MINIMAX_API_KEY=\"\${%s:-}\"\n" "$env_key_name"
    printf "  exec codex --profile minimax-m27 \"\$@\"\n"
    printf ")\n"
    printf '%s\n' "$END_MARKER"
  } >"$profile_file"

  rm -f "$tmp_file"
}

write_config_file() {
  local config_path="$1"
  local provider_base_url="$2"

  cat >"$config_path" <<EOF
# Managed by ${SCRIPT_NAME}

[model_providers.minimax]
name = "MiniMax Chat Completions API"
base_url = "${provider_base_url}"
env_key = "MINIMAX_API_KEY"
wire_api = "chat"
requires_openai_auth = false
request_max_retries = 4
stream_max_retries = 10
stream_idle_timeout_ms = 300000

[profiles.minimax-m27]
model = "MiniMax-M2.7"
model_provider = "minimax"
EOF
}

replace_file_with_backup() {
  local target_path="$1"
  shift
  local writer="$1"
  shift
  local tmp_file
  local backup_path

  tmp_file="$(mktemp)"
  "$writer" "$tmp_file" "$@"

  if [[ -f "$target_path" ]] && cmp -s "$target_path" "$tmp_file"; then
    rm -f "$tmp_file"
    log "No changes needed: ${target_path}"
    return
  fi

  mkdir -p "$(dirname "$target_path")"

  if [[ -f "$target_path" ]]; then
    backup_path="${target_path}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$target_path" "$backup_path"
    log "Backed up existing file to: ${backup_path}"
  fi

  mv "$tmp_file" "$target_path"
  log "Wrote file: ${target_path}"
}

run_codex_smoke_test() {
  local smoke_dir
  local last_message_file
  local log_file
  local -a cmd

  if ! command -v codex >/dev/null 2>&1; then
    warn "Skipping Codex smoke test because 'codex' is not installed."
    return
  fi

  if [[ -z "$API_KEY" ]]; then
    warn "Skipping Codex smoke test because ${ENV_KEY_NAME} is empty in ${ENV_FILE}."
    return
  fi

  smoke_dir="$(mktemp -d)"
  last_message_file="$(mktemp)"
  log_file="$(mktemp)"
  cmd=(
    codex
    --profile minimax-m27
    -a never
    exec
    --skip-git-repo-check
    --sandbox read-only
    --ephemeral
    -C "$smoke_dir"
    --output-last-message "$last_message_file"
    "Reply with the single word OK."
  )

  if command -v timeout >/dev/null 2>&1; then
    if env CODEX_HOME="$FINAL_CODEX_HOME" MINIMAX_API_KEY="$API_KEY" \
      timeout 90 "${cmd[@]}" >"$log_file" 2>&1; then
      log "Codex smoke test passed. Last message: $(tr '\n' ' ' < "$last_message_file" | sed 's/[[:space:]]\+/ /g')"
    else
      warn "Codex smoke test failed. Recent output: $(tail -n 20 "$log_file" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    fi
  else
    if env CODEX_HOME="$FINAL_CODEX_HOME" MINIMAX_API_KEY="$API_KEY" \
      "${cmd[@]}" >"$log_file" 2>&1; then
      log "Codex smoke test passed. Last message: $(tr '\n' ' ' < "$last_message_file" | sed 's/[[:space:]]\+/ /g')"
    else
      warn "Codex smoke test failed. Recent output: $(tail -n 20 "$log_file" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    fi
  fi

  rm -rf "$smoke_dir"
  rm -f "$last_message_file" "$log_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)
      [[ $# -ge 2 ]] || die "--api-key requires a value"
      API_KEY="$2"
      shift 2
      ;;
    --base-url)
      [[ $# -ge 2 ]] || die "--base-url requires a value"
      BASE_URL="$2"
      shift 2
      ;;
    --codex-home-root)
      [[ $# -ge 2 ]] || die "--codex-home-root requires a value"
      CODEX_HOME_ROOT="$2"
      shift 2
      ;;
    --alias)
      [[ $# -ge 2 ]] || die "--alias requires a value"
      ALIAS_NAME="$2"
      _ALIAS_FROM_CLI="1"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || die "--env-file requires a value"
      ENV_FILE="$2"
      shift 2
      ;;
    --enable-h1-proxy)
      H1_PROXY_ENABLED="true"
      shift
      ;;
    --disable-h1-proxy)
      H1_PROXY_ENABLED="false"
      shift
      ;;
    --proxy-port)
      [[ $# -ge 2 ]] || die "--proxy-port requires a value"
      H1_PROXY_PORT="$2"
      shift 2
      ;;
    --check-connectivity)
      SELF_TEST_ENABLED="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

load_env_file
resolve_api_key_from_env

# Apply env-configured alias if not overridden via CLI
if [[ -z "$_ALIAS_FROM_CLI" ]] && [[ -n "${VIBECODING_ALIAS_CODEX_MINIMAX:-}" ]]; then
  ALIAS_NAME="${VIBECODING_ALIAS_CODEX_MINIMAX}"
fi

if [[ ! "$ALIAS_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
  die "Invalid alias name: ${ALIAS_NAME}. Use letters/digits/_/- and don't start with a digit."
fi

if [[ ! "$H1_PROXY_PORT" =~ ^[0-9]+$ ]] || [[ "$H1_PROXY_PORT" -lt 1 || "$H1_PROXY_PORT" -gt 65535 ]]; then
  die "Invalid --proxy-port: ${H1_PROXY_PORT}"
fi

parse_base_url "$BASE_URL"
if [[ "$H1_PROXY_ENABLED" == "true" ]]; then
  setup_h1_proxy
  EFFECTIVE_BASE_URL="$(effective_base_url_from_proxy)"
else
  EFFECTIVE_BASE_URL="$BASE_URL"
fi

# Use a stable path so history survives container and environment changes.
FINAL_CODEX_HOME="${CODEX_HOME_ROOT%/}"
PROFILE_FILE="$(detect_profile_file)"
CONFIG_PATH="${FINAL_CODEX_HOME}/config.toml"

mkdir -p "$FINAL_CODEX_HOME"

upsert_profile_block "$PROFILE_FILE" "$FINAL_CODEX_HOME" "$ENV_FILE" "$ENV_KEY_NAME" "$ALIAS_NAME"
log "Updated profile: ${PROFILE_FILE}"

replace_file_with_backup "$CONFIG_PATH" write_config_file "$EFFECTIVE_BASE_URL"

if ! command -v codex >/dev/null 2>&1; then
  warn "'codex' command not found in PATH. Install Codex CLI first."
fi

if [[ ! -f "$ENV_FILE" ]]; then
  warn "Shared env file not found: ${ENV_FILE}"
fi

if [[ -z "$API_KEY" ]]; then
  warn "${ENV_KEY_NAME} is empty. Fill it in ${ENV_FILE} before calling model APIs."
fi

log "Final CODEX_HOME: ${FINAL_CODEX_HOME}"
log "Effective OPENAI_BASE_URL: ${EFFECTIVE_BASE_URL}"
log "Shared env file: ${ENV_FILE}"
log "Alias prepared: ${ALIAS_NAME}"

if [[ "$SELF_TEST_ENABLED" == "true" ]]; then
  run_codex_smoke_test
fi

log "Open a new shell or run: source ${PROFILE_FILE}"
