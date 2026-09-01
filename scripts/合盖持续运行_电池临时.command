#!/bin/zsh

set -u

min_remaining=10

valid_hours() {
  [[ "$1" == <-> ]] && (( 10#$1 >= 1 && 10#$1 <= 4 ))
}

on_battery() {
  /usr/bin/pmset -g batt | /usr/bin/grep -q "Battery Power"
}

if [[ "${1:-}" == "--self-test" ]]; then
  valid_hours 1
  valid_hours 4
  ! valid_hours 0
  ! valid_hours 5
  ! valid_hours abc
  print "自检通过"
  exit 0
fi

if /usr/bin/pmset -g | /usr/bin/grep -Eq 'SleepDisabled[[:space:]]+1'; then
  print "检测到合盖防睡眠已经开启。"
  read "answer?输入 R 恢复正常睡眠，其他键退出："
  if [[ "${answer:l}" == "r" ]]; then
    sudo /usr/bin/pmset -b disablesleep 0
    print "已恢复正常睡眠。"
  fi
  read "?按回车关闭窗口…"
  exit 0
fi

if ! on_battery; then
  print -u2 "请先断开电源，再启动电池临时模式。"
  read "?按回车关闭窗口…"
  exit 1
fi

hours="${1:-}"
if [[ -z "$hours" ]]; then
  read "hours?运行多少小时？输入 1–4（默认 1）："
  hours="${hours:-1}"
fi

if ! valid_hours "$hours"; then
  print -u2 "时长必须是 1–4 之间的整数。"
  read "?按回车关闭窗口…"
  exit 1
fi

hours=$((10#$hours))
seconds=$((hours * 3600))

print "即将以电池保持合盖运行 ${hours} 小时。"
print "低于 ${min_remaining}%、接上电源、到时或按 Ctrl+C 都会恢复正常睡眠。"
print "请放在通风的硬质桌面上，勿置于包内、床上或沙发上。"

sudo -v || exit 1

sudo /bin/zsh -c '
  duration="$1"
  threshold="$2"

  battery_percent() {
    /usr/bin/pmset -g batt | /usr/bin/sed -nE "s/.*([0-9]{1,3})%;.*/\\1/p" | /usr/bin/head -n 1
  }

  restore_sleep() {
    /usr/bin/pmset -b disablesleep 0
  }

  trap restore_sleep EXIT
  trap "exit 130" INT TERM HUP

  /usr/bin/pmset -b disablesleep 1
  if ! /usr/bin/pmset -g | /usr/bin/grep -Eq "SleepDisabled[[:space:]]+1"; then
    print -u2 "无法确认合盖防睡眠已开启。"
    exit 3
  fi

  print "已开启，现在可以合盖。"
  remaining="$duration"
  while (( remaining > 0 )); do
    if ! /usr/bin/pmset -g batt | /usr/bin/grep -q "Battery Power"; then
      print -u2 "检测到已接上电源，正在恢复正常睡眠。"
      exit 2
    fi
    percent="$(battery_percent)"
    if [[ ! "$percent" == <-> ]] || (( 10#$percent <= threshold )); then
      print -u2 "电量 ${percent:-未知}% 已到保护阈值，正在恢复正常睡眠。"
      exit 2
    fi
    interval=$((remaining < 30 ? remaining : 30))
    /bin/sleep "$interval"
    (( remaining -= interval ))
  done
' zsh "$seconds" "$min_remaining"
status=$?

if (( status == 0 )); then
  print "计时结束，已恢复正常睡眠。"
elif (( status == 2 )); then
  print "为保护电池而结束，已恢复正常睡眠。"
else
  print "会话已结束，已尝试恢复正常睡眠。"
fi

read "?按回车关闭窗口…"
exit "$status"
