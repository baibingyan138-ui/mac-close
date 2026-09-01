set launcherPath to "/Users/ben/Documents/ChatGPT/多agent工作/合盖持续运行_电池临时.command"

try
	set state to do shell script "/usr/bin/pmset -g | /usr/bin/grep -E 'SleepDisabled[[:space:]]+1'"
	set statusText to "当前状态：已开启合盖运行"
on error
	set statusText to "当前状态：正常休眠"
end try

set choice to choose from list {"开启临时合盖运行", "关闭并恢复正常休眠"} with title "合盖运行控制" with prompt statusText & return & return & "开启后会在终端中要求选择时长并输入管理员密码。" OK button name "继续" cancel button name "取消"
if choice is false then return

if item 1 of choice is "开启临时合盖运行" then
	try
		do shell script "/bin/test -x " & quoted form of launcherPath
		do shell script "/usr/bin/open " & quoted form of launcherPath
	on error
		display alert "无法启动" message "找不到电池临时合盖运行脚本。"
	end try
else
	try
		do shell script "/usr/bin/pmset -b disablesleep 0" with administrator privileges
		display notification "已恢复正常休眠。" with title "合盖运行控制"
	on error number -128
		return
	on error
		display alert "未能恢复休眠" message "请确认管理员密码后重试。"
	end try
end if
