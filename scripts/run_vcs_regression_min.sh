#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_TB="${ROOT_DIR}/scripts/run_vcs_tb.sh"

TESTS=(
  tb_tpu_top_m16n16k16
  tb_ewise_unit_relu_fp32
  tb_ewise_unit_relu_fp32_m16n16
  tb_tpu_top_m16n16k16_fp32_relu_fuse_min
  tb_tpu_top_direct_cmd_sequence
  tb_tpu_top_direct_cmd_explicit_ewise
  tb_execution_controller_dep_tokens
  tb_tpu_top_direct_cmd_dep_tokens
)

cd "${ROOT_DIR}"

for tb in "${TESTS[@]}"; do
  echo "==> Running ${tb}"
  "${RUN_TB}" "${tb}"
done

echo "All minimal VCS regressions passed."
