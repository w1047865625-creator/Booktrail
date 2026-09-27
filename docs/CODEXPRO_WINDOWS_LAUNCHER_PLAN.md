# Booktrail — Windows CodexPro 启动方案

> 文档性质：设计方案 / 后续实现依据  
> 状态：方案已确定，尚未开始实现 Windows 启动器  
> 更新日期：2026-09-27

## 1. 目标

为 Booktrail 配套的 Windows 开发环境提供一个极简的 CodexPro 启动方式。

最终目标不是重新实现 CodexPro，而是利用 CodexPro 当前已经提供的：

- workspace profile 持久化
- 稳定 tunnel / hostname
- CodexPro token 持久化
- `codexpro start --headless`
- `CODEXPRO_READY` 就绪信号
- runtime / child-process 生命周期管理

在 Windows 上只增加两个用户可见入口：

1. **CodexPro 启动**
2. **CodexPro 停止**

不制作托盘程序，不做复杂 GUI，不做开机自启。

---

## 2. 已确认的 CodexPro 能力

根据当前 CodexPro 官方仓库的 CHANGELOG、FAQ 和 README：

### 2.1 Workspace profile

CodexPro 从 0.19.0 开始支持按 workspace 保存 profile。

profile 默认位于：

`~/.codexpro/profiles/`

同一个 workspace 再次执行 `codexpro start` 时，会自动读取此前保存的设置。

保存内容包括：

- tunnel provider
- hostname
- local port
- mode
- CodexPro auth token
- 其他 workspace 启动设置

因此 Windows 启动器不应该自己保存这些信息。

### 2.2 Stable hostname

CodexPro 从 0.18.0 开始支持 ngrok，0.23.0 起进一步支持持久化 tunnel / hostname 设置。

当前 FAQ 明确建议日常使用稳定的 ngrok free dev domain。

例如：

`https://xxxxx.ngrok-free.dev`

使用稳定 hostname 后，ChatGPT 中保存的 MCP Server URL 不需要每次重建。

### 2.3 Headless

CodexPro 0.30.0 增加：

`codexpro start --headless`

该模式用于非交互式、后台和 service-manager 场景。

当前文档明确说明：

- 不需要交互输入
- 不进行 clipboard/browser 操作
- 会输出 `CODEXPRO_READY` 表示 ready
- HTTP runtime 意外退出时 launcher 会以非零状态退出
- 支持 runtime PID / signal cleanup

因此 Windows 启动器可以把 `CODEXPRO_READY` 作为“启动成功”的判断依据，而不是简单判断进程是否存在。

### 2.4 CodexPro 自己管理 tunnel

启动器不应该自己另外启动 ngrok。

正确职责边界：

```
Windows Launcher
    │
    └── codexpro start --headless
            │
            ├── CodexPro HTTP MCP server
            │
            ├── ngrok / tunnel
            │
            ├── workspace profile
            │
            └── runtime / cleanup
```

这样可以避免 Windows 启动器与 CodexPro 自己的 tunnel、runtime、cleanup 逻辑发生冲突。

---

## 3. 最终连接架构

完整链路：

```
ChatGPT
   │
   │ 固定 MCP Server URL
   ▼
稳定 ngrok hostname
   │
   ▼
ngrok tunnel
   │
   ▼
127.0.0.1:<CodexPro port>
   │
   ▼
CodexPro HTTP MCP server
   │
   ▼
D:\项目\Booktrail
```

Booktrail 项目本身不需要为了 ChatGPT 连接而部署到公网。

公网暴露的是 CodexPro MCP endpoint，而不是 Booktrail Web 项目或 SQLite 数据库。

---

## 4. ChatGPT 侧的一次性配置

首次完成 CodexPro setup 后：

1. 为 Booktrail workspace 配置稳定 ngrok hostname。
2. 保存 CodexPro profile。
3. 获取稳定的 MCP Server URL。
4. 在 ChatGPT 中配置一次。
5. 以后不再因为 CodexPro 重启而修改 Server URL。

典型形式：

`https://<固定ngrok域名>/mcp?codexpro_token=<token>`

注意：

- hostname 必须稳定。
- token 必须保持与 CodexPro profile 一致。
- token 不写入 GitHub。
- 本文档只描述 token 的位置和生命周期，不记录真实 token。

---

## 5. Windows 用户体验

### 5.1 不做托盘

不需要右下角常驻图标。

原因：

- CodexPro 本身负责 MCP server、tunnel 和 runtime。
- 用户没有持续操作需求。
- 托盘程序只会增加一个长期运行的额外进程。
- 当前需求只有启动和停止。

### 5.2 不做开机自启

明确不使用：

- Windows Startup
- Task Scheduler 自动启动
- Registry Run
- 服务自动启动

用户需要使用时手动启动。

### 5.3 开始菜单

最终开始菜单提供两个入口：

```
CodexPro 启动
CodexPro 停止
```

启动入口和停止入口应隐藏命令行窗口。

---

## 6. 启动流程

### 6.1 用户动作

用户点击：

**开始菜单 → CodexPro 启动**

### 6.2 启动器动作

启动器执行：

`codexpro start --headless`

工作目录必须是：

`D:\项目\Booktrail`

不要硬编码 token、hostname、port 到启动器。

### 6.3 成功判断

启动器等待 CodexPro 输出：

`CODEXPRO_READY`

只有收到该信号后才认为：

**CodexPro 已启动成功。**

成功意味着至少完成了 CodexPro 自身定义的 ready 流程，而不是单纯“Node 进程还活着”。

### 6.4 成功反馈

手动启动时：

**CodexPro 已启动 ✓**

可以使用 ChatGPT 连接。

不需要打开 CMD。

---

## 7. 启动失败

如果：

- `codexpro` 不存在
- profile 不存在或损坏
- 本地 port 被占用
- tunnel 无法建立
- hostname 不可用
- token/auth 配置异常
- HTTP runtime 启动失败
- CodexPro 未输出 `CODEXPRO_READY`

则不得提示“启动成功”。

应提示：

**CodexPro 启动失败**

并提供日志位置或诊断入口。

后续实现时需要决定日志保存位置；优先复用 CodexPro 自身输出/runtime 信息，不重新建立一套复杂日志系统。

---

## 8. 停止流程

用户点击：

**开始菜单 → CodexPro 停止**

停止器负责向 CodexPro 发出正常终止信号。

原则：

1. 不直接杀所有 Node.exe。
2. 不直接杀所有 ngrok.exe。
3. 不扫描并关闭其他 CodexPro workspace。
4. 优先使用 CodexPro 已有的 runtime / PID / cleanup 机制。
5. CodexPro 退出后由其自身清理 tunnel 和相关 child processes。

### 待实测项目

Windows 下最终采用哪一种停止方式，需要在实现阶段结合当前 CodexPro 0.30.x 的实际 runtime 文件和 Windows process behavior 实测确认。

不能仅凭“PID 存在”推断可以安全终止。

---

## 9. 启动器的职责边界

### 启动器应该负责

- 定位 CodexPro CLI
- 指定 Booktrail workspace
- 执行 `codexpro start --headless`
- 隐藏控制台窗口
- 等待 ready 信号
- 判断启动成功/失败
- 给用户一个简洁的 Windows 通知
- 在需要时保存启动日志
- 提供停止入口

### 启动器不应该负责

- 保存 CodexPro token
- 保存 ngrok hostname
- 启动第二个 ngrok
- 自己建立 MCP HTTP server
- 实现 MCP 协议
- 管理 Booktrail 数据库
- 修改 CodexPro profile
- 重写 CodexPro runtime
- 自己实现 tunnel cleanup

**核心原则：启动器是 launcher，不是 CodexPro 的替代实现。**

---

## 10. 安全要求

公网 tunnel 必须保持 CodexPro authentication。

尤其不能：

- 把真实 token 写入 GitHub
- 把 token 写进 BAT/PowerShell/VBS 源文件
- 把 token 写进 README
- 把 token 写进 Git commit
- 把 token 固定在 Windows 快捷方式参数中
- 为了方便而关闭 HTTP authentication

token 应继续由 CodexPro profile 管理。

当前 CodexPro 还对公网 HTTP authentication 做了加强，包括最小 token 长度、失败尝试限流以及 onboarding token 参数的处理。因此没有必要在 launcher 层重复实现认证。

---

## 11. 固定 URL 的关键条件

“ChatGPT 永久使用同一个 URL”并不是指 tunnel 永远在线。

它真正表示：

- hostname 固定
- CodexPro token 固定
- ChatGPT 保存的 Server URL 固定

电脑关机或 CodexPro 停止时：

**URL 仍然存在，但服务不可连接。**

重新启动 CodexPro 后：

**同一个 URL 恢复可连接。**

因此：

```
固定 URL ≠ 永久在线
固定 URL = 不需要重新配置 ChatGPT
```

---

## 12. ngrok 费用边界

本方案默认采用：

**ngrok free dev domain**

不需要购买自己的域名。

因此本方案设计目标是：

- 不购买域名
- 不购买 VPS
- 不部署服务器
- 不增加 Booktrail 云服务
- 使用 CodexPro + ngrok 免费能力

实际使用时仍应以 ngrok 当前免费套餐限制为准；不能把“免费”理解为没有流量、连接或其他套餐限制。

如果未来需要自己的域名，再考虑 Cloudflare named tunnel 等方案。

---

## 13. 为什么不直接使用 Cloudflare Quick Tunnel

Quick Tunnel 的 hostname 会变化。

因此：

```
启动 CodexPro
    ↓
获得新的 trycloudflare.com URL
    ↓
ChatGPT Server URL 改变
```

这不符合本方案“开始菜单点启动即可”的目标。

所以默认方案选择：

**ngrok free dev domain + CodexPro saved profile**

而不是 Cloudflare Quick Tunnel。

---

## 14. Windows 实现形式

最终实现可以选择以下形式之一：

### 方案 A：隐藏 PowerShell/BAT 启动器

优点：

- 简单
- 容易维护
- 几乎没有额外依赖

缺点：

- Windows 窗口隐藏、进程生命周期和停止逻辑需要仔细处理。

### 方案 B：极小型 Windows launcher

例如使用 C# / .NET 做一个无界面 launcher。

优点：

- Windows 进程管理更自然
- 可以稳定隐藏 console
- Windows 通知实现更容易
- 开始菜单快捷方式更干净

缺点：

- 多一个需要维护的二进制程序。

### 当前建议

**先不要立即决定实现语言。**

先对当前 CodexPro 0.30.x 的：

- `start --headless`
- runtime 状态文件
- PID 保存
- Windows child process
- signal handling
- cleanup

做一次源码级确认，然后再决定 A/B。

---

## 15. 后续实现顺序

严格按照以下顺序：

### 第 1 步：验证当前 CodexPro

确认：

- 当前 npm 版本
- `codexpro start --headless`
- `CODEXPRO_READY`
- runtime 文件
- PID
- profile
- Windows 进程行为

### 第 2 步：手动验证完整链路

在：

`D:\项目\Booktrail`

执行正式 CodexPro 启动流程。

确认：

```
CodexPro HTTP server
        +
stable ngrok tunnel
        +
ChatGPT MCP connection
```

均正常。

### 第 3 步：实现 Windows 启动入口

实现：

**CodexPro 启动**

要求：

- 无 CMD 窗口
- 等待 ready
- 成功通知
- 失败通知
- 不保存敏感配置

### 第 4 步：实现 Windows 停止入口

实现：

**CodexPro 停止**

要求：

- 使用 CodexPro 自身 runtime/process 信息
- 正常终止
- 等待退出
- 验证 tunnel cleanup
- 不误杀其他进程

### 第 5 步：安装到开始菜单

最终：

```
开始菜单
└── Booktrail
    ├── CodexPro 启动
    └── CodexPro 停止
```

不加入启动项。

不创建托盘常驻程序。

### 第 6 步：完整验证

至少验证：

1. 冷启动电脑后手动启动。
2. 启动成功通知。
3. ChatGPT 可以连接。
4. CodexPro 修改 Booktrail 文件正常。
5. 停止。
6. 确认 tunnel 退出。
7. 再启动。
8. ChatGPT 仍使用同一个 Server URL。
9. CodexPro profile 没有被 launcher 破坏。
10. launcher 本身没有泄露 token。

---

## 16. 最终目标状态

用户最终只需要记住：

### 第一次

完成 CodexPro setup + ngrok stable hostname + ChatGPT MCP 配置。

### 以后每次

```
开始菜单
  ↓
CodexPro 启动
  ↓
“CodexPro 已启动 ✓”
  ↓
直接使用 ChatGPT
```

使用完：

```
开始菜单
  ↓
CodexPro 停止
```

不需要：

- 改 URL
- 重新配置 ChatGPT
- 启动 ngrok
- 输入 token
- 打开 CMD
- 操作托盘
- 修改 Booktrail
- 部署服务器

---

## 17. 重要设计结论

本方案的核心不是“写一个复杂的 CodexPro 管理器”。

而是：

> **让 Windows 只成为 CodexPro 的一个干净启动/停止入口，所有实际连接、认证、profile、tunnel 和生命周期逻辑继续由 CodexPro 自己负责。**

这样可以最大限度复用作者已经实现并验证的能力，也能降低未来 CodexPro 更新导致 Booktrail 启动器失效的风险。

---

## 18. 参考资料

- CodexPro CHANGELOG：`0.19.0` profile、`0.23.0` 持久化 tunnel、`0.30.0` headless。
- CodexPro FAQ：stable ngrok dev domain、profile、headless、Windows/runtime 相关说明。
- CodexPro 中文 FAQ：稳定 URL、headless、profile 与安全边界。

官方仓库：
https://github.com/rebel0789/codexpro

官方 CHANGELOG：
https://github.com/rebel0789/codexpro/blob/main/CHANGELOG.md

官方 FAQ：
https://github.com/rebel0789/codexpro/blob/main/FAQ.md

---

## 19. 实现前的硬性约束

后续真正开始实现时必须遵守：

1. **先重新读取本文件。**
2. **先检查当前 CodexPro 源码/版本，再写 launcher。**
3. 不假定 runtime 文件名或 PID 结构没有变化。
4. 不假定 Windows signal 行为，必须实测。
5. 不自己实现 tunnel。
6. 不自己保存 token。
7. 不修改 CodexPro 源码来适配 launcher，除非有明确、经过验证的必要性。
8. 不把 token、个人路径以外的敏感信息提交到 GitHub。
9. launcher 修改前先进行本地/模拟验证。
10. 如果 CodexPro 已经提供对应能力，优先调用官方能力，而不是复制实现。
