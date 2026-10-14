#!/bin/bash
# Demo data for `mo status`, `mo analyze` and `mo uninstall --list`, used by fake-mo.sh
# when FAKE_MO_DEMO=1 (README screenshots). Read-only: it only prints JSON.

status_json() {
  # Light jitter so the live cards move like the real thing.
  local r=$((RANDOM % 20))
  local c1=$((38 + RANDOM % 30)) c2=$((30 + RANDOM % 30)) c3=$((22 + RANDOM % 30)) c4=$((18 + RANDOM % 25))
  local c5=$((12 + RANDOM % 20)) c6=$((10 + RANDOM % 20)) e1=$((6 + RANDOM % 18)) e2=$((5 + RANDOM % 16))
  local e3=$((4 + RANDOM % 14)) e4=$((4 + RANDOM % 12)) e5=$((3 + RANDOM % 12)) e6=$((3 + RANDOM % 10))
  local usage=$(((c1 + c2 + c3 + c4 + c5 + c6 + e1 + e2 + e3 + e4 + e5 + e6) / 12))
  local down rx
  down=$(awk -v r="$r" 'BEGIN { printf "%.2f", 0.4 + r / 9 }')
  rx=$(awk -v r="$r" 'BEGIN { printf "%.2f", 0.05 + r / 60 }')
  printf '{"host":"demo","uptime":"6d 4h","health_score":88,"health_score_msg":"Excellent",'
  printf '"hardware":{"model":"MacBook Pro","cpu_model":"Apple M3 Pro","total_ram":"18.0 GB","os_version":"macOS 15.1"},'
  printf '"cpu":{"usage":%d,"per_core":[%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d],"p_core_count":6,"e_core_count":6,"logical_cpu":12},' \
    "$usage" "$e1" "$e2" "$e3" "$e4" "$e5" "$e6" "$c1" "$c2" "$c3" "$c4" "$c5" "$c6"
  printf '"memory":{"used":13100000000,"total":19327352832,"swap_used":2254857830,"pressure":"normal"},'
  printf '"disk_io":{"read_rate":%d,"write_rate":%d},' $((30 + RANDOM % 40)) $((6 + RANDOM % 12))
  printf '"network":[{"name":"en0","rx_rate_mbs":%s,"tx_rate_mbs":%s,"ip":"192.168.1.20"}],' "$down" "$rx"
  printf '"batteries":[{"percent":82,"status":"charging","health":"Good","cycle_count":212,"capacity":94}],'
  printf '"thermal":{"cpu_temp":%d,"battery_temp":31,"adapter_power":67},' $((48 + RANDOM % 6))
  printf '"top_processes":['
  printf '{"pid":101,"name":"node","cpu":%d.%d,"memory_bytes":966367641},' $((18 + RANDOM % 8)) $((RANDOM % 10))
  printf '{"pid":102,"name":"Google Chrome Helper (Renderer)","cpu":%d.%d,"memory_bytes":2040109465},' $((10 + RANDOM % 8)) $((RANDOM % 10))
  printf '{"pid":103,"name":"Figma","cpu":%d.%d,"memory_bytes":1503238553},' $((6 + RANDOM % 8)) $((RANDOM % 10))
  printf '{"pid":104,"name":"WindowServer","cpu":%d.%d,"memory_bytes":641728512},' $((6 + RANDOM % 5)) $((RANDOM % 10))
  printf '{"pid":105,"name":"kernel_task","cpu":%d.%d,"memory_bytes":220200960},' $((4 + RANDOM % 5)) $((RANDOM % 10))
  printf '{"pid":106,"name":"Xcode","cpu":%d.%d,"memory_bytes":3006477107}' $((2 + RANDOM % 6)) $((RANDOM % 10))
  printf ']}\n'
}

entry() { printf '{"name":"%s","path":"%s","size":%s,"is_dir":%s,"scan_status":"complete"}' "$1" "$2" "$3" "$4"; }

analyze_json() {
  local path="$1" sep="" name size dir
  local -a rows=()
  case "$path" in
    "$HOME")
      rows=("Library|71000000000|true" "Pictures|56000000000|true" "Movies|46700000000|true" "code|26900000000|true"
            "Downloads|18600000000|true" "Documents|12200000000|true" ".cache|12500000000|true" "Music|8400000000|true" ".npm|3200000000|true") ;;
    "$HOME/Library")
      rows=("Application Support|58600000000|true" "Containers|26900000000|true" "Developer|27200000000|true" "Caches|9600000000|true"
            "Messages|6200000000|true" "Mail|2600000000|true") ;;
    "$HOME/code")
      rows=("ml-experiments|14700000000|true" "mobile-app|7800000000|true" "rust-cli|3410000000|true" "web-app|1730000000|true" "design-system|1080000000|true") ;;
    *)
      rows=("node_modules|1600000000|true" "build|4800000000|true" "src|200000000|true" "README.md|12000|false") ;;
  esac
  printf '{"scan_status":"complete","path":"%s","overview":false,"entries":[' "$path"
  local total=0
  for row in "${rows[@]}"; do
    IFS='|' read -r name size dir <<< "$row"
    printf '%s' "$sep"; entry "$name" "$path/$name" "$size" "$dir"; sep=","
    total=$((total + size))
  done
  printf '],"total_size":%d}\n' "$total"
}

# Built-in apps only, so screenshots show nothing personal.
uninstall_json() {
  local sep="" app id
  printf '['
  for row in "Chess|com.apple.Chess" "Stickies|com.apple.Stickies" "TextEdit|com.apple.TextEdit" "Photo Booth|com.apple.PhotoBooth" \
             "Calculator|com.apple.calculator" "Font Book|com.apple.FontBook" "Grapher|com.apple.grapher" "Image Capture|com.apple.Image_Capture"; do
    IFS='|' read -r app id <<< "$row"
    local path="/System/Applications/$app.app"
    [[ -d "$path" ]] || path="/System/Applications/Utilities/$app.app"
    [[ -d "$path" ]] || continue
    printf '%s\n  {"name": "%s", "bundle_id": "%s", "source": "App", "uninstall_name": "%s", "path": "%s", "size": "--"}' "$sep" "$app" "$id" "$app" "$path"
    sep=","
  done
  printf '\n]\n'
}

case "$1" in
  status)
    if [[ "$2" == "--watch" ]]; then
      parent=$PPID
      for _ in $(seq 1 3600); do
        kill -0 "$parent" 2>/dev/null || exit 0
        status_json || exit 0
        sleep 1
      done
    else
      status_json
    fi ;;
  analyze) analyze_json "${@: -1}" ;;
  uninstall) [[ "$2" == "--list" ]] && uninstall_json ;;
esac
exit 0
