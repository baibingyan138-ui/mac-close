#!/bin/zsh

set -u

min_remaining=10

valid_hours() {
  [[ "$1" == <-> ]] && (( 10#$1 >= 1 && 10#$1 <= 4 ))
}

valid_duration() {
  valid_hours "$1" || [[ "$1" == unlimited ]]
}

on_battery() {
  /usr/bin/pmset -g batt | /usr/bin/grep -q "Battery Power"
}

if [[ "${1:-}" == "--self-test" ]]; then
  sample=$' -InternalBattery-0\t75%; discharging'
  parsed="$(print -r -- "$sample" | /usr/bin/sed -nE 's/.*[[:space:]]([0-9]{1,3})%;.*/\1/p')"
  lid_sample='"AppleClamshellState" = Yes'
  low_power_sample='lowpowermode 0'
  low_power="$(print -r -- "$low_power_sample" | /usr/bin/awk '$1 == "lowpowermode" { print $2 }')"
  if valid_hours 1 && valid_hours 4 && valid_duration unlimited && ! valid_duration 0 && ! valid_duration forever &&
      ! valid_hours abc && [[ "$parsed" == 75 ]] && [[ "$low_power" == 0 ]] &&
      print -r -- "$lid_sample" | /usr/bin/grep -q '"AppleClamshellState" = Yes'; then
    print "自检通过"
    exit 0
  fi
  print -u2 "自检失败"
  exit 1
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

if ! /usr/sbin/sysadminctl -screenLock status 2>&1 | /usr/bin/grep -q "delay is immediate"; then
  print -u2 "请先在系统设置 > 锁定屏幕中，将关闭显示器后要求输入密码设为立即。"
  read "?按回车关闭窗口…"
  exit 1
fi

hours="${1:-}"
if [[ -z "$hours" ]]; then
  read "hours?运行多少小时？输入 1–4 或 unlimited（默认 1）："
  hours="${hours:-1}"
fi

if ! valid_duration "$hours"; then
  print -u2 "时长必须是 1–4 之间的整数，或 unlimited。"
  read "?按回车关闭窗口…"
  exit 1
fi

unlimited=0
if [[ "$hours" == unlimited ]]; then
  seconds=0
  unlimited=1
  duration_label="不限时"
else
  hours=$((10#$hours))
  seconds=$((hours * 3600))
  duration_label="${hours} 小时"
fi

print "即将以电池保持合盖运行 ${duration_label}。"
print "低于 ${min_remaining}%、接上电源、到时或按 Ctrl+C 都会恢复正常睡眠。"
print "合盖后会自动锁屏并进入低电量模式，开盖后恢复原有模式。"
print "请放在通风的硬质桌面上，勿置于包内、床上或沙发上。"

sudo -v || exit 1

sudo /bin/zsh -c '
  duration="$1"
  threshold="$2"
  unlimited="$3"

  current_low_power_mode() {
    /usr/bin/pmset -g | /usr/bin/awk "\$1 == \"lowpowermode\" { print \$2; exit }"
  }

  original_low_power="$(current_low_power_mode)"
  if [[ "$original_low_power" != <-> ]] || (( original_low_power < 0 || original_low_power > 1 )); then
    print -u2 "无法读取当前低电量模式。"
    exit 3
  fi
  low_power_applied=0

  restore_low_power() {
    if (( low_power_applied )); then
      /usr/bin/pmset -b lowpowermode "$original_low_power"
      low_power_applied=0
    fi
  }

  battery_percent() {
    /usr/bin/pmset -g batt | /usr/bin/sed -nE "s/.*[[:space:]]([0-9]{1,3})%;.*/\\1/p" | /usr/bin/head -n 1
  }

  restore_sleep() {
    restore_low_power
    /usr/bin/pmset -b disablesleep 0
  }

  lid_closed() {
    /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | /usr/bin/grep -q "\"AppleClamshellState\" = Yes"
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
  was_closed=0
  while (( unlimited || remaining > 0 )); do
    if ! /usr/bin/pmset -g batt | /usr/bin/grep -q "Battery Power"; then
      print -u2 "检测到已接上电源，正在恢复正常睡眠。"
      exit 2
    fi
    percent="$(battery_percent)"
    if [[ ! "$percent" == <-> ]] || (( 10#$percent <= threshold )); then
      print -u2 "电量 ${percent:-未知}% 已到保护阈值，正在恢复正常睡眠。"
      exit 2
    fi
    if lid_closed; then
      if (( ! was_closed )); then
        /usr/bin/pmset -b lowpowermode 1
        low_power_applied=1
        /usr/bin/pmset displaysleepnow
        print "检测到合盖，屏幕已锁定并进入低电量模式。"
        was_closed=1
      fi
    else
      restore_low_power
      was_closed=0
    fi
    interval=2
    if (( ! unlimited && remaining < interval )); then
      interval="$remaining"
    fi
    /bin/sleep "$interval"
    if (( ! unlimited )); then
      (( remaining -= interval ))
    fi
  done
' zsh "$seconds" "$min_remaining" "$unlimited"
exit_status=$?

if (( exit_status == 0 )); then
  print "计时结束，已恢复正常睡眠。"
elif (( exit_status == 2 )); then
  print "为保护电池而结束，已恢复正常睡眠。"
else
  print "会话已结束，已尝试恢复正常睡眠。"
fi

read "?按回车关闭窗口…"
exit "$exit_status"
