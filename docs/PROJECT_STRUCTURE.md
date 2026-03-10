# Project Structure (Digital IC Style)

## Top-Level Layout

- `rtl/`: RTL design sources
- `tb/`: simple/direct testbenches
- `dv/`: verification environment (UVM, coverage)
- `scripts/`: utilities, data processing, perf tools
- `data/`: datasets and vectors
- `docs/`: specs, reports, plans
- `reports/`: EDA generated reports (synth/place/route/timing)

## Current Mapping

- `rtl/core/` <= old `Design/`
- `tb/sv/` <= old `Testbench/`
- `dv/uvm/` <= old `UVM/`
- `scripts/utils/` <= old `Scripts/`
- `data/dataset/` <= old `Dataset/`

## Notes

- New files should prefer the standardized paths above.
- Legacy path aliases have been removed. Please use only standardized paths.
