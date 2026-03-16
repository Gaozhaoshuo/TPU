#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <tb_name_without_extension> [sim_args...]"
  exit 1
fi

TB_NAME="$1"
shift || true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/reports/vcs/${TB_NAME}"
TB_FILE="${ROOT_DIR}/tb/sv/${TB_NAME}.sv"
RTL_FILELIST="${ROOT_DIR}/tb/filelist/rtl_core.f"
MDIR="${BUILD_DIR}/csrc"

if [[ ! -f "${TB_FILE}" ]]; then
  echo "tb file not found: ${TB_FILE}"
  exit 1
fi

mkdir -p "${BUILD_DIR}"
cd "${ROOT_DIR}"

vcs -full64 -sverilog -timescale=1ns/1ps \
  -Mdir="${MDIR}" \
  -f "${RTL_FILELIST}" \
  "${TB_FILE}" \
  -o "${BUILD_DIR}/simv" \
  -l "${BUILD_DIR}/compile.log"

"${BUILD_DIR}/simv" "$@" -l "${BUILD_DIR}/sim.log"
