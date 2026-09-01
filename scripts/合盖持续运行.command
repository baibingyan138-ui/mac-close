#!/bin/zsh

set -u

valid_hours() {
  [[ "$1" == <-> ]] && (( 10#$1 >= 1 && 10#$1 <= 24 ))
}

if [[ "${1:-}" == "--self-test" ]]; then
  valid_hours 1
  valid_hours 24
  ! valid_hours 0
  ! valid_hours 25
  ! valid_hours abc
  print "自检通过"
  exit 0
fi

if /usr/bin/pmset -g | /usr/bin/grep -Eq 'SleepDisabled[[:space:]]+1'; then
  print "检测到合盖防睡眠已经开启。"
  read "answer?输入 R 恢复正常睡眠，其他键退出："
  if [[ "${answer:l}" == "r" ]]; then
    sudo /usr/bin/pmset -a disablesleep 0
    print "已恢复正常睡眠。"
  fi
  read "?按回车关闭窗口…"
  exit 0
fi

if ! /usr/bin/pmset -g batt | /usr/bin/grep -q "AC Power"; then
  print -u2 "请先连接电源，再启动合盖运行。"
  read "?按回车关闭窗口…"
  exit 1
fi

hours="${1:-}"
if [[ -z "$hours" ]]; then
  read "hours?运行多少小时？输入 1–24（默认 4）："
  hours="${hours:-4}"
fi

if ! valid_hours "$hours"; then
  print -u2 "时长必须是 1–24 之间的整数。"
  read "?按回车关闭窗口…"
  exit 1
fi

hours=$((10#$hours))
seconds=$((hours * 3600))

print "即将保持合盖运行 ${hours} 小时。"
print "期间请接电源并放在通风的硬质桌面上。"
print "到时、断开电源或按 Ctrl+C 后会自动恢复正常睡眠。"

sudo -v || exit 1

sudo /bin/zsh -c '
  duration="$1"

  restore_sleep() {
    /usr/bin/pmset -a disablesleep 0
  }

  trap restore_sleep EXIT
  trap "exit 130" INT TERM HUP

  /usr/bin/pmset -a disablesleep 1
  if ! /usr/bin/pmset -g | /usr/bin/grep -Eq "SleepDisabled[[:space:]]+1"; then
    print -u2 "无法确认合盖防睡眠已开启。"
    exit 3
  fi

  print "已开启，现在可以合盖。"
  remaining="$duration"
  while (( remaining > 0 )); do
    if ! /usr/bin/pmset -g batt | /usr/bin/grep -q "AC Power"; then
      print -u2 "检测到电源已断开，正在恢复正常睡眠。"
      exit 2
    fi
    interval=$((remaining < 30 ? remaining : 30))
    /bin/sleep "$interval"
    (( remaining -= interval ))
  done
' zsh "$seconds"
status=$?

if (( status == 0 )); then
  print "计时结束，已恢复正常睡眠。"
elif (( status == 2 )); then
  print "因电源断开而结束，已恢复正常睡眠。"
else
  print "会话已结束，已尝试恢复正常睡眠。"
fi

read "?按回车关闭窗口…"
exit "$status"
