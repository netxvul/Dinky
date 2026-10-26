# 启用 Dock 脚本扩展（scripting-addition）滚动

这是一份把 scrolling 布局的 Dock 脚本扩展滚动从零开到能用的完整步骤文档。

> 一句话：它通过往 Dock 注入一段载荷，借 Dock 的特权连接**直接移动真实窗口**来做滚动动画，比逐帧移动窗口更顺，而且**列能平滑滑出屏幕左右边缘**。代价是必须**关闭 SIP**，并且偏实验性。没注入时不起作用。

---

## 一、能看到的区别

开启并生效后：

- 滚动动画走真实窗口、满 120Hz，更顺；
- 滚动时**列可以平滑地滑过屏幕左右边缘**，而不是停在边缘只露一小条（25pt）。
- 钉住的列（pin）始终压在其它窗口之上，包括当前激活应用的窗口（需要 0.4.0 的载荷；更新后重新运行 `scripts/build-sa.sh`）。没有它时，激活应用的窗口滑过 pin 会盖住 pin。

没生效 / 回退时：列只停在屏幕边缘露一条——这就是判断它「到底有没有在工作」的最直观标志。

---

## 二、前提条件（缺一不可）

1. **SIP 的 Filesystem Protections + Debugging Restrictions 关闭**；
2. NVRAM 里有 boot-arg **`-arm64e_preview_abi`**；
3. 已经把 dinky 的脚本扩展**注入到 Dock**（下面第四步做）。

检查当前是否满足 1、2：

```bash
csrutil status
nvram boot-args
```

`Filesystem Protections: disabled`、`Debugging Restrictions: disabled`，且 boot-args 里有 `-arm64e_preview_abi`，就说明 1、2 已满足，可**直接跳到第四步**。

---

## 三、关闭 SIP（如果上一步不满足才需要做）

> 已经满足就跳过。SIP 开着时无法注入，dinky 会**干净回退**到逐帧移动窗口，不影响正常使用。

Apple Silicon：

1. 关机。长按电源键直到出现「正在载入启动选项」，点**选项 → 继续**进入恢复模式。
2. 顶部菜单 **实用工具 → 终端**，执行：
   ```
   csrutil disable
   ```
   （按提示确认；这会关闭 Filesystem Protections 和 Debugging Restrictions。）
3. 正常重启回 macOS，设置 boot-arg（需要管理员密码）：
   ```bash
   sudo nvram boot-args=-arm64e_preview_abi
   ```
4. 再重启一次让 boot-arg 生效。

---

## 四、编译并注入脚本扩展

在仓库根目录执行（需要 root，会提示输密码）：

```bash
bash scripts/build-sa.sh
```

它会：编译 payload 和 loader（arm64e）→ 组装成 `dinky.osax` → 安装到 `/Library/ScriptingAdditions/dinky.osax` → 注入当前的 Dock。看到结尾打印：

```
OK: scripting addition loaded (/tmp/dinky-sa_<你的用户名>.socket)
```

就表示注入成功、载荷已在 Dock 里监听。

更新载荷（例如升级 dinky 后）也是重跑这一步：已经载入 Dock 的旧载荷在 Dock 重启前不会被换掉，所以脚本发现旧载荷在运行时会先重启一次 Dock，再注入新的。

---

## 五、开机 / Dock 重启后自动重注入（推荐）

注入的载荷会随 **Dock 重启或重开机而失效**。装一条免密 sudoers，dinky 检测到失效时会自己重新注入（带退避，不会把 Dock 拖进重启循环）：

```bash
printf '%s ALL=(root) NOPASSWD: /Library/ScriptingAdditions/dinky.osax/Contents/MacOS/loader\n' "$USER" \
  | sudo tee /etc/sudoers.d/dinky >/dev/null \
  && sudo chmod 440 /etc/sudoers.d/dinky \
  && sudo visudo -cf /etc/sudoers.d/dinky
```

不装这条也能用，只是每次 Dock 重启后要手动再跑一遍第四步。

---

## 六、改配置

编辑 `~/.config/dinky/dinky.toml`，保存后 dinky 会自动热重载。只需顶层（第一个 `[表]` 之前）：

```toml
scripting-addition = true
```

这是默认值，一般本来就是 true，什么都不用改。设成 `false` 则无论如何都不碰 SA。

滚动走哪条路只看这一项：为 true 且 Dock 里的扩展在应答时走扩展滑动；否则（false、未注入、SIP 开着）一律逐帧移动真实窗口。
旧版的 `[scrolling] glide` 已经取消，配置里还写着也不会报错，`dinky doctor` 会提示可以删掉。

---

## 七、验证是否生效

- 看 socket 在不在：
  ```bash
  ls -l /tmp/dinky-sa_$USER.socket
  ```
- 看 dinky 日志里的注入结果：
  ```bash
  grep -i reinject ~/Library/Logs/dinky.log | tail
  ```
- 最直观：到一个有多列窗口的 scrolling 工作区**左右滚动**，看列是否能平滑滑过屏幕边缘。

---

## 八、关闭 / 卸载

- **停用**：顶层 `scripting-addition = false`。SA 立即停用，dinky 不再探测/注入，滚动改为逐帧移动窗口。
- **从系统里清除安装物**：
  ```bash
  sudo rm -rf /etc/sudoers.d/dinky /Library/ScriptingAdditions/dinky.osax
  rm -f /tmp/dinky-sa_$USER.socket
  ```

---

## 九、工作原理（简述）

dinky 自己的 WindowServer 连接无权移动别的 App 的窗口；Dock 的连接有。所以把一段载荷（`Sources/DinkyPrivate/osax/payload.m`）注入 Dock，dinky 通过 unix socket 指挥它逐帧移动/变换窗口。滚动时载荷每帧通过 Dock 的连接直接移动真实窗口，不经过 app，所以不会有哪个 app 慢了落在后面，窗口也能滑出 Accessibility 会限制的屏幕边缘；滚动结束后才通过 Accessibility 写入窗口位置，app 发现窗口已经在那里，不会再移动它。旧版载荷不能批量移动窗口，仍用变换显示滑动。注入器 `loader.m` 派生自 yabai 的 `src/osax/loader.m`（MIT）。

---

## 十、故障排查

- **跑了 build-sa.sh 但滚动没变化**：确认顶层 `scripting-addition` 没设成 false（第六步），并确认 socket 真的在（第七步）。只有 socket 文件没进程在听也不行——重跑第四步。
- **用着用着又失效了**：多半是 Dock 重启过，载荷随之没了。装了第五步的 sudoers 就会自动补回来；没装就手动重跑第四步。
- **Dock 反复重启 / 桌面闪**：历史上遇到过载荷让 Dock 崩的问题（SIGPIPE，已修）。如果再现，先 `sudo rm /etc/sudoers.d/dinky` 停掉自动重注入让桌面稳定，再排查。
- **开了 SIP 之后**：注入会失败，dinky 自动回退到逐帧移动窗口，不会报错也不会卡住。

---

**建议**：不想折腾 SIP 和注入就什么都不用做，滚动会逐帧移动真实窗口。SA 这套主要是为了更顺和「列滑出边缘」的效果，按需启用。
