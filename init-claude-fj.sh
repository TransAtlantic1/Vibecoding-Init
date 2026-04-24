#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Early env load to pick up VIBECODING_DATA_ROOT for default paths
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a; set +u; . "${SCRIPT_DIR}/.env"; set -u; set +a
fi

WORKSPACE_ROOT="${VIBECODING_DATA_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"

SCRIPT_NAME="init-claude-fj.sh"
LOG_TAG="init-claude"
BEGIN_MARKER="# >>> claude init >>>"
END_MARKER="# <<< claude init <<<"

DEFAULT_AUTH_TOKEN=""
DEFAULT_BASE_URL="https://timesniper.club"
DEFAULT_CLAUDE_HOME_ROOT="${WORKSPACE_ROOT}/.claude_home"
DEFAULT_ALIAS="claude"
DEFAULT_MAX_OUTPUT_TOKENS="64000"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_ENV_KEY_NAME="CLAUDE_AUTH_TOKEN"

AUTH_TOKEN="${DEFAULT_AUTH_TOKEN}"
BASE_URL="${DEFAULT_BASE_URL}"
CLAUDE_HOME_ROOT="${DEFAULT_CLAUDE_HOME_ROOT}"
ALIAS_NAME="${DEFAULT_ALIAS}"
MAX_OUTPUT_TOKENS="${DEFAULT_MAX_OUTPUT_TOKENS}"
ENV_FILE="${DEFAULT_ENV_FILE}"
ENV_KEY_NAME="${DEFAULT_ENV_KEY_NAME}"

_ALIAS_FROM_CLI=""

HOST_OR_CONTAINER=""
VENV_NAME=""
FINAL_HOME=""
PROFILE_FILE=""
SETTINGS_DIR=""
SETTINGS_PATH=""
ONBOARDING_PATH=""

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [options]

Options:
  --auth-token <token>        Anthropic auth token (optional, defaults to ${ENV_KEY_NAME} in ${ENV_FILE}).
  --base-url <url>            Claude provider base URL (default: ${DEFAULT_BASE_URL}).
  --claude-home-root <dir>    Root dir for isolated Claude HOME (default: \$HOME/fj/.claude_home).
  --alias <name>              Shell function name (default: ${DEFAULT_ALIAS}).
  --max-output-tokens <n>     CLAUDE_CODE_MAX_OUTPUT_TOKENS (default: ${DEFAULT_MAX_OUTPUT_TOKENS}).
  --env-file <path>           Shared .env file (default: ${DEFAULT_ENV_FILE}).
  -h, --help                  Show this help message.
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

resolve_auth_token_from_env() {
  local resolved=""

  if [[ -n "$AUTH_TOKEN" ]]; then
    return
  fi

  if [[ -n "$ENV_KEY_NAME" ]]; then
    resolved="${!ENV_KEY_NAME:-}"
  fi

  AUTH_TOKEN="${resolved}"
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

upsert_profile_block() {
  local profile_file="$1"
  local final_home="$2"
  local settings_path="$3"
  local env_file="$4"
  local env_key_name="$5"
  local alias_name="$6"
  local tmp_file
  local escaped_home
  local escaped_settings
  local escaped_env_file

  escaped_home="$(escape_single_quotes "$final_home")"
  escaped_settings="$(escape_single_quotes "$settings_path")"
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
    printf "export CLAUDE_HOME='%s'\n" "$escaped_home"
    printf "export CLAUDE_ENV_FILE='%s'\n" "$escaped_env_file"
    printf "%s() (\n" "$alias_name"
    printf "  export HOME='%s'\n" "$escaped_home"
    printf "  if [[ -f '%s' ]]; then\n" "$escaped_env_file"
    printf "    set -a\n"
    printf "    source '%s'\n" "$escaped_env_file"
    printf "    set +a\n"
    printf "  fi\n"
    printf "  export ANTHROPIC_AUTH_TOKEN=\"\${%s:-}\"\n" "$env_key_name"
    printf "  exec claude --settings '%s' \"\$@\"\n" "$escaped_settings"
    printf ")\n"
    printf '%s\n' "$END_MARKER"
  } >"$profile_file"

  rm -f "$tmp_file"
}

write_settings_file() {
  local path="$1"

  cat >"$path" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "${BASE_URL}",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "${MAX_OUTPUT_TOKENS}",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "permissions": { "allow": [], "deny": [] },
  "alwaysThinkingEnabled": false
}
EOF
}

write_onboarding_file() {
  local path="$1"

  cat >"$path" <<'EOF'
{ "hasCompletedOnboarding": true }
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auth-token)
      [[ $# -ge 2 ]] || die "--auth-token requires a value"
      AUTH_TOKEN="$2"
      shift 2
      ;;
    --base-url)
      [[ $# -ge 2 ]] || die "--base-url requires a value"
      BASE_URL="$2"
      shift 2
      ;;
    --claude-home-root)
      [[ $# -ge 2 ]] || die "--claude-home-root requires a value"
      CLAUDE_HOME_ROOT="$2"
      shift 2
      ;;
    --alias)
      [[ $# -ge 2 ]] || die "--alias requires a value"
      ALIAS_NAME="$2"
      _ALIAS_FROM_CLI="1"
      shift 2
      ;;
    --max-output-tokens)
      [[ $# -ge 2 ]] || die "--max-output-tokens requires a value"
      MAX_OUTPUT_TOKENS="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || die "--env-file requires a value"
      ENV_FILE="$2"
      shift 2
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
resolve_auth_token_from_env

# Apply env-configured alias if not overridden via CLI
if [[ -z "$_ALIAS_FROM_CLI" ]] && [[ -n "${VIBECODING_ALIAS_CLAUDE:-}" ]]; then
  ALIAS_NAME="${VIBECODING_ALIAS_CLAUDE}"
fi

if [[ ! "$ALIAS_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
  die "Invalid alias name: ${ALIAS_NAME}. Use letters/digits/_/- and don't start with a digit."
fi

if [[ ! "$MAX_OUTPUT_TOKENS" =~ ^[0-9]+$ ]] || [[ "$MAX_OUTPUT_TOKENS" -lt 1 ]]; then
  die "Invalid --max-output-tokens: ${MAX_OUTPUT_TOKENS}"
fi

# Use a stable path so history survives container and environment changes.
FINAL_HOME="${CLAUDE_HOME_ROOT%/}"
PROFILE_FILE="$(detect_profile_file)"
SETTINGS_DIR="${FINAL_HOME}/.claude"
SETTINGS_PATH="${SETTINGS_DIR}/settings.json"
ONBOARDING_PATH="${FINAL_HOME}/.claude.json"

mkdir -p "$SETTINGS_DIR"

upsert_profile_block "$PROFILE_FILE" "$FINAL_HOME" "$SETTINGS_PATH" "$ENV_FILE" "$ENV_KEY_NAME" "$ALIAS_NAME"
log "Updated profile: ${PROFILE_FILE}"

replace_file_with_backup "$SETTINGS_PATH" write_settings_file
replace_file_with_backup "$ONBOARDING_PATH" write_onboarding_file

if ! command -v claude >/dev/null 2>&1; then
  warn "'claude' command not found in PATH. Install Claude Code first."
fi

if [[ ! -f "$ENV_FILE" ]]; then
  warn "Shared env file not found: ${ENV_FILE}"
fi

if [[ -z "$AUTH_TOKEN" ]]; then
  warn "${ENV_KEY_NAME} is empty. Fill it in ${ENV_FILE} before calling Claude Code."
fi

log "Final isolated HOME: ${FINAL_HOME}"
log "Settings path: ${SETTINGS_PATH}"
log "Shared env file: ${ENV_FILE}"
log "Function prepared: ${ALIAS_NAME}"
log "Open a new shell or run: source ${PROFILE_FILE}"
