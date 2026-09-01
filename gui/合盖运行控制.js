ObjC.import("stdlib");

const app = Application.currentApplication();
app.includeStandardAdditions = true;
const launcher = "/Users/ben/Documents/ChatGPT/多agent工作/合盖持续运行_电池临时.command";

let enabled = false;
try {
  app.doShellScript("/usr/bin/pmset -g | /usr/bin/grep -q 'SleepDisabled[[:space:]]\\+1'");
  enabled = true;
} catch (_) {}

const choice = app.chooseFromList(
  ["开启临时合盖运行", "关闭并恢复正常休眠"],
  {
    withTitle: "合盖运行控制",
    withPrompt: `当前状态：${enabled ? "已开启合盖运行" : "正常休眠"}\n\n开启后会在终端中要求选择时长并输入管理员密码。`,
    okButtonName: "继续",
    cancelButtonName: "取消",
  },
);

if (choice) {
  if (choice[0] === "开启临时合盖运行") {
    try {
      app.doShellScript(`/bin/test -x ${JSON.stringify(launcher)} && /usr/bin/open ${JSON.stringify(launcher)}`);
    } catch (_) {
      app.displayAlert("无法启动", {message: "找不到电池临时合盖运行脚本。"});
    }
  } else {
    try {
      app.doShellScript("/usr/bin/pmset -b disablesleep 0", {withAdministratorPrivileges: true});
      app.displayNotification("已恢复正常休眠。", {withTitle: "合盖运行控制"});
    } catch (error) {
      if (String(error).indexOf("User canceled") === -1) {
        app.displayAlert("未能恢复休眠", {message: "请确认管理员密码后重试。"});
      }
    }
  }
}
