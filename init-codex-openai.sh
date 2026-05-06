#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  set +u
  # shellcheck disable=SC1090
  . "${SCRIPT_DIR}/.env"
  set -u
  set +a
fi

WORKSPACE_ROOT="${VIBECODING_DATA_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"

SCRIPT_NAME="init-codex-openai.sh"
LOG_TAG="init-codex-openai"
OLD_BEGIN_MARKER="# >>> codex init >>>"
OLD_END_MARKER="# <<< codex init <<<"
OLD_FJ_BEGIN_MARKER="# >>> codex-fj init >>>"
OLD_FJ_END_MARKER="# <<< codex-fj init <<<"
BEGIN_MARKER="# >>> codex-openai init >>>"
END_MARKER="# <<< codex-openai init <<<"

DEFAULT_CODEX_HOME_ROOT="${WORKSPACE_ROOT}/.codex_home"
DEFAULT_ALIAS="codex-openai"
DEFAULT_CLASH_DIR="${WORKSPACE_ROOT}/clash"

CODEX_HOME_ROOT="${VIBECODING_CODEX_OPENAI_HOME:-${DEFAULT_CODEX_HOME_ROOT}}"
ALIAS_NAME="${DEFAULT_ALIAS}"
CLASH_DIR="${DEFAULT_CLASH_DIR}"
PROFILE_UPDATE_ENABLED="true"
START_CLASH_ENABLED="true"
AUTH_WRITE_ENABLED="true"

_ALIAS_FROM_CLI=""

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [options]

Options:
  --codex-home-root <dir>  CODEX_HOME dir (default: ${DEFAULT_CODEX_HOME_ROOT}).
  --alias <name>           Shell function name (default: ${DEFAULT_ALIAS}).
  --clash-dir <dir>        Clash dir (default: ${DEFAULT_CLASH_DIR}).
  --no-profile             Do not update the shell profile alias block.
  --no-start-clash         Do not auto-start Clash when 7890/7891 are not listening.
  --skip-auth-write        Do not write auth.json from CODEX_OPENAI_AUTH_JSON.
  -h, --help               Show this help message.

Notes:
  This script writes auth.json from CODEX_OPENAI_AUTH_JSON in ${SCRIPT_DIR}/.env.
  To export Clash proxy variables into the already-open shell, run:
    source ${SCRIPT_NAME}
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
  return 1 2>/dev/null || exit 1
}

is_sourced() {
  [[ "${BASH_SOURCE[0]}" != "$0" ]]
}

escape_single_quotes() {
  local val="$1"
  printf "%s" "$val" | sed "s/'/'\\\\''/g"
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

port_listening() {
  local port="$1"
  ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .
}

ensure_clash_running() {
  if port_listening 7890 && port_listening 7891; then
    log "Clash proxy is already listening at 127.0.0.1:7890/7891"
    return
  fi

  if [[ "${START_CLASH_ENABLED}" != "true" ]]; then
    warn "Clash is not listening at 127.0.0.1:7890/7891 and --no-start-clash was set."
    return
  fi

  if [[ ! -x "${CLASH_DIR}/start.sh" ]]; then
    die "Clash is not running and start script is missing or not executable: ${CLASH_DIR}/start.sh"
  fi

  log "Starting Clash from ${CLASH_DIR}"
  "${CLASH_DIR}/start.sh"

  if ! port_listening 7890 || ! port_listening 7891; then
    die "Clash did not start HTTP/SOCKS proxy on 127.0.0.1:7890/7891"
  fi
}

export_clash_proxy_for_current_shell() {
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  export HTTP_PROXY="http://127.0.0.1:7890"
  export HTTPS_PROXY="http://127.0.0.1:7890"
  export all_proxy="socks5://127.0.0.1:7891"
  export ALL_PROXY="socks5://127.0.0.1:7891"
}

write_config_file() {
  local config_path="$1"

  cat >"${config_path}" <<'EOF'
model_provider = "openai"
model = "gpt-5.5"
model_reasoning_effort = "high"
personality = "pragmatic"

[plugins."notion@openai-curated"]
enabled = true

[plugins."github@openai-curated"]
enabled = true

[plugins."hugging-face@openai-curated"]
enabled = true

[plugins."documents@openai-primary-runtime"]
enabled = true

[plugins."spreadsheets@openai-primary-runtime"]
enabled = true

[plugins."presentations@openai-primary-runtime"]
enabled = true

[plugins."browser-use@openai-bundled"]
enabled = true

[mcp_servers]

[mcp_servers.feishu]
type = "stdio"
command = "npx"
args = ["-y", "@larksuiteoapi/lark-mcp", "mcp", "-a", "cli_a95dddeaa6f99ceb", "-s", "fC6cFXVSEtKKj2L5wi4OQfH0LZuncjeA", "--oauth", "--token-mode", "user_access_token", "-t", "preset.default,docx.v1.document.get,docx.v1.document.create,docx.v1.documentBlock.get,docx.v1.documentBlock.list,docx.v1.documentBlock.patch,docx.v1.documentBlock.batchUpdate,docx.v1.documentBlockChildren.get,docx.v1.documentBlockChildren.create,docx.v1.documentBlockChildren.batchDelete,docx.v1.documentBlockDescendant.create,docx.v1.document.convert,drive.v1.fileComment.get,drive.v1.fileComment.list,drive.v1.fileComment.create,drive.v1.fileComment.patch,drive.v1.fileComment.batchQuery,drive.v1.fileCommentReply.list,drive.v1.fileCommentReply.update,drive.v1.fileCommentReply.delete,drive.v1.permissionMember.list,drive.v1.permissionMember.update,wiki.v1.node.search"]

[marketplaces.openai-bundled]
last_updated = "2026-05-04T04:23:30Z"
source_type = "local"
source = "/Users/fangjie/.codex/.tmp/bundled-marketplaces/openai-bundled"

[marketplaces.openai-primary-runtime]
last_updated = "2026-05-02T03:46:43Z"
source_type = "local"
source = "/Users/fangjie/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime"

[projects."/Users/fangjie/Documents/codex project/备份恢复切换工具"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/code/rubric_pipeline"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/vibecoding工具"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/Codex/2026-04-24/gihub-private-public-star-watching-github"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/qizhi-trans"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/Codex/2026-04-27/jupyterbook"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/Codex/2026-04-27/jupyterbook-2"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/Codex/2026-04-27/new-chat"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/创智报名"]
trust_level = "trusted"

[projects."/Users/fangjie/Documents/codex-wechat"]
trust_level = "trusted"

[tui.model_availability_nux]
"gpt-5.5" = 3
EOF
}

replace_file() {
  local target_path="$1"
  shift
  local writer="$1"
  shift
  local tmp_file

  tmp_file="$(mktemp)"
  "$writer" "$tmp_file" "$@"

  if [[ -f "$target_path" ]] && cmp -s "$target_path" "$tmp_file"; then
    rm -f "$tmp_file"
    log "No changes needed: ${target_path}"
    return
  fi

  mkdir -p "$(dirname "$target_path")"
  mv "$tmp_file" "$target_path"
  log "Wrote file: ${target_path}"
}

write_auth_json_from_env() {
  local auth_path="$1"
  local auth_json="${CODEX_OPENAI_AUTH_JSON:-}"

  if [[ -z "$auth_json" ]]; then
    die "CODEX_OPENAI_AUTH_JSON is empty in ${SCRIPT_DIR}/.env"
  fi

  mkdir -p "$(dirname "$auth_path")"
  printf '%s\n' "$auth_json" >"$auth_path"
  chmod 600 "$auth_path"
  log "Wrote auth.json from CODEX_OPENAI_AUTH_JSON: ${auth_path}"
}

upsert_profile_block() {
  local profile_file="$1"
  local codex_home="$2"
  local clash_dir="$3"
  local alias_name="$4"
  local tmp_file
  local escaped_home
  local escaped_clash_dir

  escaped_home="$(escape_single_quotes "$codex_home")"
  escaped_clash_dir="$(escape_single_quotes "$clash_dir")"
  tmp_file="$(mktemp)"

  touch "$profile_file"

  awk \
    -v old_begin="$OLD_BEGIN_MARKER" \
    -v old_end="$OLD_END_MARKER" \
    -v old_fj_begin="$OLD_FJ_BEGIN_MARKER" \
    -v old_fj_end="$OLD_FJ_END_MARKER" \
    -v begin="$BEGIN_MARKER" \
    -v end="$END_MARKER" '
      $0 == old_begin || $0 == old_fj_begin || $0 == begin {skip=1; next}
      $0 == old_end || $0 == old_fj_end || $0 == end {skip=0; next}
      !skip {print}
    ' "$profile_file" >"$tmp_file"

  {
    cat "$tmp_file"
    printf '\n%s\n' "$BEGIN_MARKER"
    printf "export CODEX_OPENAI_HOME='%s'\n" "$escaped_home"
    printf "export CODEX_OPENAI_CLASH_DIR='%s'\n" "$escaped_clash_dir"
    printf "%s() (\n" "$alias_name"
    printf "  export CODEX_HOME='%s'\n" "$escaped_home"
    printf "  if [[ ! -f \"\$CODEX_HOME/auth.json\" ]]; then\n"
    printf "    printf \"codex-openai: missing %%s; run init-codex-openai.sh after filling CODEX_OPENAI_AUTH_JSON in .env.\\\\n\" \"\$CODEX_HOME/auth.json\" >&2\n"
    printf "    return 1\n"
    printf "  fi\n"
    printf "  unset OPENAI_API_KEY OPENAI_BASE_URL CODEX_API_KEY\n"
    printf "  export http_proxy='http://127.0.0.1:7890'\n"
    printf "  export https_proxy='http://127.0.0.1:7890'\n"
    printf "  export HTTP_PROXY='http://127.0.0.1:7890'\n"
    printf "  export HTTPS_PROXY='http://127.0.0.1:7890'\n"
    printf "  export all_proxy='socks5://127.0.0.1:7891'\n"
    printf "  export ALL_PROXY='socks5://127.0.0.1:7891'\n"
    printf "  exec codex \"\$@\"\n"
    printf ")\n"
    printf '%s\n' "$END_MARKER"
  } >"$profile_file"

  rm -f "$tmp_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --clash-dir)
      [[ $# -ge 2 ]] || die "--clash-dir requires a value"
      CLASH_DIR="$2"
      shift 2
      ;;
    --no-profile)
      PROFILE_UPDATE_ENABLED="false"
      shift
      ;;
    --no-start-clash)
      START_CLASH_ENABLED="false"
      shift
      ;;
    --skip-auth-write)
      AUTH_WRITE_ENABLED="false"
      shift
      ;;
    -h|--help)
      usage
      return 0 2>/dev/null || exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

if [[ -z "$_ALIAS_FROM_CLI" ]] && [[ -n "${VIBECODING_ALIAS_CODEX:-}" ]]; then
  ALIAS_NAME="${VIBECODING_ALIAS_CODEX}"
elif [[ -z "$_ALIAS_FROM_CLI" ]] && [[ -n "${VIBECODING_ALIAS_CODEX_OPENAI:-}" ]]; then
  ALIAS_NAME="${VIBECODING_ALIAS_CODEX_OPENAI}"
fi

if [[ ! "$ALIAS_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
  die "Invalid alias name: ${ALIAS_NAME}. Use letters/digits/_/- and do not start with a digit."
fi

FINAL_CODEX_HOME="${CODEX_HOME_ROOT%/}"
CONFIG_PATH="${FINAL_CODEX_HOME}/config.toml"
AUTH_PATH="${FINAL_CODEX_HOME}/auth.json"
PROFILE_FILE="$(detect_profile_file)"

mkdir -p "$FINAL_CODEX_HOME"

replace_file "$CONFIG_PATH" write_config_file
if [[ "$AUTH_WRITE_ENABLED" == "true" ]]; then
  write_auth_json_from_env "$AUTH_PATH"
else
  warn "Skipped auth.json write because --skip-auth-write was set."
fi

ensure_clash_running

if [[ "$PROFILE_UPDATE_ENABLED" == "true" ]]; then
  upsert_profile_block "$PROFILE_FILE" "$FINAL_CODEX_HOME" "$CLASH_DIR" "$ALIAS_NAME"
  log "Updated profile: ${PROFILE_FILE}"
else
  warn "Skipped profile update because --no-profile was set."
fi

if ! command -v codex >/dev/null 2>&1; then
  warn "'codex' command not found in PATH."
fi

if is_sourced; then
  export CODEX_HOME="$FINAL_CODEX_HOME"
  export_clash_proxy_for_current_shell
  unset OPENAI_API_KEY OPENAI_BASE_URL CODEX_API_KEY
  log "Current shell now uses CODEX_HOME=${CODEX_HOME}"
  log "Current shell now uses Clash proxy at 127.0.0.1:7890/7891"
else
  warn "A child process cannot export proxy variables into its parent shell."
  warn "For this already-open terminal, run: source ${SCRIPT_DIR}/${SCRIPT_NAME}"
fi

log "Alias prepared: ${ALIAS_NAME}"
log "Final CODEX_HOME: ${FINAL_CODEX_HOME}"
log "Config path: ${CONFIG_PATH}"
