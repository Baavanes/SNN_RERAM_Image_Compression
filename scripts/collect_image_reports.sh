#!/usr/bin/env bash
set -euo pipefail

RUN=/home/vboxuser/IMPACT_SNN_RERAM_submit_BMsemi/openlane/user_project_wrapper/runs/image_compression_harden_20260624_175512
METRICS="$RUN/final/metrics.csv"
RTL_LOG=/home/vboxuser/impact_runs/image_compression_rtl_nowave_20260624_174122.log

echo "== RTL COCOTB =="
grep -E "TESTS=|X1 image|Cycles consumed|Test passed" "$RTL_LOG" || true

echo
echo "== FINAL VIEWS =="
ls -lh \
  /home/vboxuser/IMPACT_SNN_RERAM_submit_BMsemi/gds/user_project_wrapper.gds \
  /home/vboxuser/IMPACT_SNN_RERAM_submit_BMsemi/def/user_project_wrapper.def \
  /home/vboxuser/IMPACT_SNN_RERAM_submit_BMsemi/lef/user_project_wrapper.lef \
  /home/vboxuser/IMPACT_SNN_RERAM_submit_BMsemi/lib/user_project_wrapper.lib \
  /home/vboxuser/IMPACT_SNN_RERAM_submit_BMsemi/spef/user_project_wrapper.spef \
  /home/vboxuser/IMPACT_SNN_RERAM_submit_BMsemi/verilog/gl/user_project_wrapper.v

echo
echo "== METRICS =="
while IFS=, read -r key value rest; do
  case "$key" in
    design__violations|route__drc_errors|magic__drc_error__count|klayout__drc_error__count|\
    design__xor_difference__count|design__lvs_error__count|design__lvs_device_difference__count|\
    design__lvs_net_difference__count|design__lvs_property_fail__count|design__lvs_unmatched_device__count|\
    design__lvs_unmatched_net__count|design__lvs_unmatched_pin__count|antenna__violating__nets|\
    antenna__violating__pins|route__antenna_violation__count|timing__setup__wns|timing__setup__tns|\
    timing__hold__wns|timing__hold__tns|design__max_cap_violation__count|design__max_slew_violation__count|\
    design__max_fanout_violation__count|design__lint_warning__count|design__lint_error__count|\
    design__instance_unmapped__count)
      printf '%s,%s\n' "$key" "$value"
      ;;
  esac
done < "$METRICS"

echo
echo "== CORNER VIOLATIONS =="
grep -E "^(timing__(setup|hold)__.*(wns|tns)|design__max_(cap|slew|fanout)_violation__count__corner),|^design__max_(cap|slew|fanout)_violation__count," "$METRICS" || true

echo
echo "== MAGIC DRC =="
cat "$RUN/62-magic-drc/reports/drc_violations.magic.rpt"

echo
echo "== KLAYOUT DRC COUNT =="
grep "klayout__drc_error__count" "$METRICS" || true

echo
echo "== LVS =="
grep -E "Circuit 1 contains|Final result|Circuits match|errors" "$RUN/68-netgen-lvs/reports/lvs.netgen.rpt" | tail -n 20 || true

echo
echo "== XOR =="
grep -E "Total XOR differences|design__xor_difference__count|XOR differences" "$RUN/60-klayout-xor/klayout-xor.log" | tail -n 20 || true

echo
echo "== ANTENNA SUMMARY =="
cat "$RUN/46-openroad-checkantennas-1/reports/antenna_summary.rpt" || true

echo
echo "== ANTENNA DETAIL =="
grep -n -E "Violation|violating|P/R|Partial|Required|Net |Pin:|Layer:" "$RUN/46-openroad-checkantennas-1/openroad-checkantennas-1.log" | tail -n 120 || true

echo
echo "== FLOW LOG SUMMARY =="
grep -E "Flow complete|Antenna|LVS|DRC|Max Slew|Max Cap|No setup|No hold|violations found" /home/vboxuser/impact_runs/image_compression_harden_20260624_175512.log | tail -n 80 || true
