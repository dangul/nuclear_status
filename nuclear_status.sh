#!/usr/bin/env bash
# nuclear_status.sh v6 - Swedish nuclear power status (Nord Pool UMM)
set -uo pipefail

UMM_API="${UMM_API:-https://ummapi.nordpoolgroup.com/messages?limit=500}"
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
NOW_EPOCH=$(date -u +%s)

# ---------- Colors (disabled if not a terminal or NO_COLOR is set) ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'
  B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  R=; G=; Y=; C=; B=; D=; N=
fi

# ---------- Fetch with retry ----------
for i in 1 2 3; do
  curl -fsS --max-time 30 -H "Accept: application/json" "$UMM_API" -o "$TMP" && break
  [[ $i -eq 3 ]] && { echo "${R}API unreachable (HTTP error)${N}" >&2; exit 2; }
  sleep 5
done

fmt() { TZ=Europe/Stockholm date -d "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$1"; }

declare -A RE=(
  ["Forsmark 1"]="Forsmark.*(Block ?1)"
  ["Forsmark 2"]="Forsmark.*(Block ?2)"
  ["Forsmark 3"]="Forsmark.*(Block ?3)"
  ["Oskarshamn 3"]="Oskarshamn.*(Block ?3)"
  ["Ringhals 3"]="Ringhals.*(Block ?3)"
  ["Ringhals 4"]="Ringhals.*(Block ?4)"
)

W=64
line() { printf '%s' "$D"; printf '%*s' "$W" '' | tr ' ' '-'; printf '%s\n' "$N"; }

echo
echo "${B}${C}  SWEDISH NUCLEAR POWER STATUS${N}"
echo "${D}  $(TZ=Europe/Stockholm date '+%Y-%m-%d %H:%M %Z')  |  Source: Nord Pool UMM${N}"
line

DRIFT=0; REDUCED=0; DOWN=0; TOTAL_INST=0; TOTAL_AVAIL=0

for name in "Forsmark 1" "Forsmark 2" "Forsmark 3" "Oskarshamn 3" "Ringhals 3" "Ringhals 4"; do
  res=$(jq -c --arg re "${RE[$name]}" --argjson now "$NOW_EPOCH" '
    def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    (.items // .messages // .data // .) | if type=="array" then . else [] end
    | map(select(.isOutdated == false and .productionUnits != null))
    | [ .[] as $m
        | $m.productionUnits[]
        | select(.name | test($re; "i")) as $u
        | $u.timePeriods[]
        | select((.eventStart|ts) <= $now and (.eventStop|ts) >= $now)
        | {installed: $u.installedCapacity, avail: .availableCapacity,
           stop: .eventStop, reason: $m.unavailabilityReason,
           remarks: ($m.remarks // ""), type: $m.unavailabilityType,
           pub: $m.publicationDate} ]
    | sort_by(.pub) | last // empty' "$TMP")

  # Installed capacity for totals (from any message mentioning this unit)
  inst_any=$(jq -r --arg re "${RE[$name]}" '
    (.items // .messages // .data // .) | if type=="array" then . else [] end
    | [ .[] | select(.productionUnits != null) | .productionUnits[]
        | select(.name | test($re; "i")) | .installedCapacity ] | first // 0' "$TMP")

  if [[ -z "$res" ]]; then
    printf "  ${G}●${N} ${B}%-14s${N} ${G}OPERATING${N}  ${D}(no active outage messages)${N}\n" "$name"
    ((DRIFT++))
    TOTAL_INST=$((TOTAL_INST + inst_any)); TOTAL_AVAIL=$((TOTAL_AVAIL + inst_any))
    continue
  fi

  avail=$(jq -r .avail <<<"$res"); inst=$(jq -r .installed <<<"$res")
  stop=$(jq -r .stop <<<"$res");   reason=$(jq -r .reason <<<"$res")
  remarks=$(jq -r .remarks <<<"$res"); typ=$(jq -r .type <<<"$res")
  [[ "$typ" == "1" ]] && typtxt="Unplanned" || typtxt="Planned"
  TOTAL_INST=$((TOTAL_INST + inst)); TOTAL_AVAIL=$((TOTAL_AVAIL + avail))

  if [[ "$avail" == "0" ]]; then
    pct=0; col=$R; icon="✖"; status="OFFLINE"; ((DOWN++))
  else
    pct=$(( avail * 100 / inst )); col=$Y; icon="▲"
    status="REDUCED ${pct}%"; ((REDUCED++))
  fi

  # Power bar (20 chars)
  filled=$(( pct * 20 / 100 )); bar=""
  for ((k=0; k<20; k++)); do [[ $k -lt $filled ]] && bar+="█" || bar+="░"; done

  printf "  ${col}${icon}${N} ${B}%-14s${N} ${col}${B}%s${N}\n" "$name" "$status"
  printf "      Output:   ${col}%s${N} %d%%  ${D}(%s of %s MW)${N}\n" "$bar" "$pct" "$avail" "$inst"
  printf "      Type:     %s\n" "$typtxt"
  printf "      Reason:   %s\n" "$reason"

  # Remarks: flatten newlines, trim
  rem=$(tr '\n' ' ' <<<"$remarks" | sed 's/  */ /g; s/^ //; s/ $//')
  [[ -n "$rem" ]] && printf "      Info:     ${D}%s${N}\n" "${rem:0:220}"

  if [[ "$avail" == "0" ]]; then
    # Event stop = technically available again; ramp-up time only if stated in remarks
    printf "      Available:      ${C}%s${N}  ${D}(event stop, local time)${N}\n" "$(fmt "$stop")"
    hrs=$(grep -oiE 'approx\.? *[0-9]+ ?h' <<<"$rem" | grep -oE '[0-9]+' | head -1)
    if [[ -n "$hrs" ]]; then
      est=$(TZ=Europe/Stockholm date -d "${stop%.*}Z + ${hrs} hours" '+%Y-%m-%d %H:%M' 2>/dev/null)
      [[ -n "$est" ]] && printf "      Full power est: ${C}%s${N}  ${D}(+~%sh ramp-up per operator remarks)${N}\n" "$est" "$hrs"
    fi
  else
    printf "      Full power:     ${C}%s${N}  ${D}(end of reduced period, local time)${N}\n" "$(fmt "$stop")"
  fi
  echo
done

line
total=$((DRIFT + REDUCED + DOWN))
cap_pct=0; [[ $TOTAL_INST -gt 0 ]] && cap_pct=$(( TOTAL_AVAIL * 100 / TOTAL_INST ))
printf "  ${B}Summary:${N} ${G}%d operating${N} | ${Y}%d reduced${N} | ${R}%d offline${N}  ${D}(of %d reactors)${N}\n" \
  "$DRIFT" "$REDUCED" "$DOWN" "$total"
printf "  ${B}Capacity:${N} %d of %d MW available (%d%%)\n" "$TOTAL_AVAIL" "$TOTAL_INST" "$cap_pct"
echo