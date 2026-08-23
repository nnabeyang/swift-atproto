#!/usr/bin/env bash
#
# Build this package's DocC documentation locally.
#
# The Swift Package Index builds and hosts the published documentation from
# `.spi.yml`. This script reads the same manifest so that a local build covers
# exactly the targets the index publishes, using the same documentation
# parameters. It never writes into the repository; documentation output is not
# committed.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: scripts/build-documentation.sh [--strict] [--output <dir>]
       scripts/build-documentation.sh --preview <target> [--port <port>]

  (no arguments)     Build every target listed in .spi.yml and report failures.
  --strict           Treat DocC warnings as errors.
  --output <dir>     Keep the generated archives in <dir> instead of a
                     temporary directory that is removed on exit.
  --preview <target> Serve one target's documentation for local browsing.
  --port <port>      Port for --preview (default: 8080).
USAGE
}

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly manifest_path="${repository_root}/.spi.yml"

# The Swift Package Index serves documentation from
# `swiftpackageindex.com/<owner>/<repository>/<reference>/documentation/<target>`,
# and passes that prefix to DocC as the hosting base path. Mirroring it locally
# keeps generated links in the same shape as the published ones.
hosting_base_path="${DOCC_HOSTING_BASE_PATH:-nnabeyang/swift-atproto/main}"
bundle_identifier_prefix="com.nnabeyang.swift-atproto"

strict=false
output_path=""
preview_target=""
preview_port=8080

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --strict)
      strict=true
      shift
      ;;
    --output)
      [[ "$#" -ge 2 ]] || { usage; exit 64; }
      output_path="$2"
      shift 2
      ;;
    --preview)
      [[ "$#" -ge 2 ]] || { usage; exit 64; }
      preview_target="$2"
      shift 2
      ;;
    --port)
      [[ "$#" -ge 2 ]] || { usage; exit 64; }
      preview_port="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unrecognized argument: %s\n' "$1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -n "${preview_target}" && -n "${output_path}" ]]; then
  printf 'error: --preview and --output are mutually exclusive\n' >&2
  exit 64
fi

if [[ ! -f "${manifest_path}" ]]; then
  printf 'error: Swift Package Index manifest is missing: %s\n' "${manifest_path}" >&2
  exit 1
fi

# Reads a YAML sequence from .spi.yml, accepting both the block form
# (`key:` followed by `- item` lines) and the inline form (`key: [a, b]`). The
# key itself may be the first key of a list item, so a leading `- ` is allowed.
read_manifest_sequence() {
  local key="$1"
  awk -v key="${key}" '
    function emit(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["\x27]|["\x27]$/, "", value)
      if (value != "") print value
    }
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
    }
    line ~ ("^[[:space:]]*(-[[:space:]]+)?" key ":[[:space:]]*\\[") {
      inline = line
      sub(/^[^[]*\[/, "", inline)
      sub(/\].*$/, "", inline)
      count = split(inline, items, ",")
      for (index_ = 1; index_ <= count; index_++) emit(items[index_])
      next
    }
    line ~ ("^[[:space:]]*(-[[:space:]]+)?" key ":[[:space:]]*$") {
      collecting = 1
      next
    }
    collecting && line ~ /^[[:space:]]*-[[:space:]]*/ {
      item = line
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      emit(item)
      next
    }
    collecting && line ~ /^[[:space:]]*[^[:space:]]/ {
      collecting = 0
    }
  ' "${manifest_path}"
}

targets=()
while IFS= read -r target; do
  targets+=("${target}")
done < <(read_manifest_sequence documentation_targets)

if [[ "${#targets[@]}" == 0 ]]; then
  printf 'error: no documentation_targets found in %s\n' "${manifest_path}" >&2
  exit 1
fi

# `custom_documentation_parameters` is passed through to DocC by the index, so
# a local build has to pass it too.
custom_parameters=()
while IFS= read -r parameter; do
  custom_parameters+=("${parameter}")
done < <(read_manifest_sequence custom_documentation_parameters)

if [[ -n "${preview_target}" ]]; then
  found=false
  for target in "${targets[@]}"; do
    [[ "${target}" == "${preview_target}" ]] && found=true
  done
  if [[ "${found}" == false ]]; then
    printf 'error: %s is not listed in documentation_targets: %s\n' \
      "${preview_target}" "${targets[*]}" >&2
    exit 64
  fi
  targets=("${preview_target}")
fi

if command -v docc >/dev/null 2>&1; then
  docc_command=(docc)
elif command -v xcrun >/dev/null 2>&1; then
  docc_command=(xcrun docc)
else
  printf 'error: neither docc nor xcrun is available\n' >&2
  exit 1
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/swift-atproto-documentation.XXXXXX")"
readonly temporary_directory
trap 'rm -rf -- "${temporary_directory}"' EXIT

if [[ -n "${output_path}" ]]; then
  mkdir -p "${output_path}"
  archives_directory="$(cd -- "${output_path}" && pwd)"
else
  archives_directory="${temporary_directory}/archives"
  mkdir -p "${archives_directory}"
fi

# Emits the symbol graphs for one target and copies just that module's graphs
# into a directory of its own. A single build directory also collects the
# graphs of every dependency, which DocC would otherwise document as well.
symbol_graph_directory_for() {
  local target="$1"
  local build_directory="${temporary_directory}/symbol-graph-build/${target}"
  local module_directory="${temporary_directory}/symbol-graphs/${target}"
  mkdir -p "${build_directory}" "${module_directory}"

  # Each target is built separately: passing several `--target` options to one
  # `swift build` invocation does not emit a symbol graph for every target.
  swift build --package-path "${repository_root}" \
    --target "${target}" \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir -Xswiftc "${build_directory}" \
    >&2

  if [[ ! -f "${build_directory}/${target}.symbols.json" ]]; then
    printf 'error: no symbol graph was emitted for %s\n' "${target}" >&2
    return 1
  fi

  local graph_path
  for graph_path in "${build_directory}/${target}.symbols.json" \
    "${build_directory}/${target}@"*.symbols.json; do
    [[ -f "${graph_path}" ]] || continue
    cp "${graph_path}" "${module_directory}/"
  done

  printf '%s\n' "${module_directory}"
}

docc_options_for() {
  local target="$1"
  printf '%s\n' \
    --additional-symbol-graph-dir "$2" \
    --fallback-display-name "${target}" \
    --fallback-bundle-identifier "${bundle_identifier_prefix}.${target}"
  if [[ "${#custom_parameters[@]}" -gt 0 ]]; then
    printf '%s\n' "${custom_parameters[@]}"
  fi
}

if [[ -n "${preview_target}" ]]; then
  symbol_graph_directory="$(symbol_graph_directory_for "${preview_target}")"
  options=()
  while IFS= read -r option; do
    options+=("${option}")
  done < <(docc_options_for "${preview_target}" "${symbol_graph_directory}")

  exec "${docc_command[@]}" preview \
    "${repository_root}/Sources/${preview_target}/Documentation.docc" \
    --port "${preview_port}" \
    --output-path "${archives_directory}/${preview_target}.doccarchive" \
    "${options[@]}"
fi

failed_targets=()
for target in "${targets[@]}"; do
  catalog_path="${repository_root}/Sources/${target}/Documentation.docc"
  if [[ ! -d "${catalog_path}" ]]; then
    printf 'error: documentation catalog is missing: %s\n' "${catalog_path}" >&2
    failed_targets+=("${target}")
    continue
  fi

  printf '==> Building documentation for %s\n' "${target}" >&2

  if ! symbol_graph_directory="$(symbol_graph_directory_for "${target}")"; then
    failed_targets+=("${target}")
    continue
  fi

  options=()
  while IFS= read -r option; do
    options+=("${option}")
  done < <(docc_options_for "${target}" "${symbol_graph_directory}")
  if [[ "${strict}" == true ]]; then
    options+=(--warnings-as-errors)
  fi

  if "${docc_command[@]}" convert "${catalog_path}" \
    --output-path "${archives_directory}/${target}.doccarchive" \
    --transform-for-static-hosting \
    --hosting-base-path "${hosting_base_path}" \
    "${options[@]}"; then
    :
  else
    failed_targets+=("${target}")
  fi
done

if [[ "${#failed_targets[@]}" -gt 0 ]]; then
  printf 'error: documentation build failed for: %s\n' "${failed_targets[*]}" >&2
  exit 1
fi

printf 'Built documentation for: %s\n' "${targets[*]}" >&2
if [[ -n "${output_path}" ]]; then
  printf 'Archives are in %s.\n' "${archives_directory}" >&2
fi
