# Booktrail

**Booktrail v4.6.0** 是一款运行于 **Kindle 原生系统**的本地阅读统计工具，用于记录和整理阅读轨迹。

## 功能

- 📚 记录阅读时间与阅读会话
- 📖 按书籍查看阅读进度与累计阅读时长
- 📅 查看每日、每周、每月及年度阅读数据
- 📊 分析阅读习惯与阅读量
- 💾 数据保存在 Kindle 本地，不依赖云服务
- ⚡ 针对 Kindle 硬件环境设计

## 安装前提

- Kindle 已完成越狱
- 已安装并可以正常使用 **KUAL（Kindle Unified Application Launcher）**
- 使用 Kindle 原生阅读系统
- 建议使用已验证的 Kindle 固件 **5.17.1.0.4**

> Booktrail 面向越狱 Kindle 用户，不适用于未越狱设备，也不会替换 Kindle 原有阅读器。

## 安装教程

### 1. 准备安装包

下载对应版本的安装包：

```text
Booktrail-4.6.0.zip
```

请使用与当前版本匹配的安装包，不要混用不同版本的文件。

### 2. 安装 Booktrail 主程序

将 ZIP 安装包中的 Booktrail 主程序完整解压到：

```text
/mnt/us/extensions/booktrail/
```

安装完成后，目录结构应类似于：

```text
/mnt/us/extensions/booktrail/
├── bin/
│   ├── kindle-reading-gtk
│   ├── booktrail-session-append
│   ├── krg_collector.sh
│   ├── metrics.sh
│   ├── metrics_setup.sh
│   └── ...
├── etc/
│   └── syslog-ng.conf
├── config.xml
└── menu.json
```

**注意：不要多嵌套一层目录。**

错误示例：

```text
/mnt/us/extensions/booktrail/Booktrail-4.6.0/bin/
```

正确示例：

```text
/mnt/us/extensions/booktrail/bin/
```

### 3. 安装 Kindle 主页显示入口

安装包中的：

```text
documents/Booktrail.sh
```

用于在 Kindle 主页显示 Booktrail 入口。

将这个文件复制到 Kindle 的：

```text
/mnt/us/documents/
```

最终路径应为：

```text
/mnt/us/documents/Booktrail.sh
```

不要把整个 `documents` 文件夹复制进去，也不要修改 `Booktrail.sh` 的文件名。

安装完成后，返回 Kindle 主页即可看到 Booktrail 的入口；点击该入口即可启动 Booktrail。

> 这个文件只是 Kindle 主页的启动入口，Booktrail 主程序本体仍然必须安装在 `/mnt/us/extensions/booktrail/`。

### 4. 打开 KUAL

1. 安全断开 Kindle 与电脑的连接。
2. 在 Kindle 上打开 **KUAL**。
3. 找到 **Booktrail 阅读统计**。
4. 点击菜单项启动 Booktrail 图形界面。

如果 KUAL 中没有出现 Booktrail，请检查：

- `config.xml` 是否位于 `/mnt/us/extensions/booktrail/` 根目录；
- `menu.json` 是否存在；
- 是否错误地多嵌套了一层文件夹；
- 关闭并重新打开 KUAL，必要时重新插拔 USB 连接。

### 5. 首次启动与数据库

首次打开时，Booktrail 会检查本地数据库：

- 数据库不存在时，尝试初始化数据库；
- 数据库存在时，执行数据库校验；
- 数据库默认位置：

```text
/mnt/us/extensions/booktrail/booktrail.db
```

升级版本时，程序会尝试创建数据库备份：

```text
/mnt/us/extensions/booktrail/booktrail.pre-4.6.0.db
```

请勿随意删除数据库或备份文件，以免造成阅读统计数据丢失。

## 阅读数据采集

后台采集由以下组件负责：

- `krg_collector.sh`：阅读事件采集器
- `booktrail-session-append`：将阅读会话写入 SQLite 数据库
- `metrics_setup.sh`：采集配置的启用、停用和统计数据重置
- `booktrail-start.sh` / `booktrail-stop.sh`：启动或停止采集器

采集配置涉及 Kindle 的 `syslog-ng` 系统配置。**不要直接覆盖 Kindle 原有的 syslog-ng 配置文件**，应使用项目提供的配置管理脚本，以保留校验和回滚逻辑。

> 当前 KUAL 菜单主要提供图形界面入口。若安装后没有自动采集，请先确认安装包完整、目录路径正确，再检查当前版本对应的采集启用流程；不要手动删除或覆盖系统日志配置。

## 安装验证

建议按以下顺序检查：

1. Kindle 主页能够看到 **Booktrail** 入口；
2. 点击主页入口能够启动 Booktrail；
3. KUAL 中能够看到 **Booktrail 阅读统计**；
4. 点击 KUAL 菜单后能够打开图形界面；
5. Kindle 上出现 `booktrail.db`；
6. 阅读一段时间后重新打开 Booktrail，检查统计数据是否变化；
7. 如果 GUI 无法启动，优先检查安装目录、可执行文件和数据库初始化状态。

## 卸载注意事项

卸载前应先停止 Booktrail 后台采集，并保留数据库备份。

同时删除 Kindle 主页入口文件：

```text
/mnt/us/documents/Booktrail.sh
```

不要直接删除 Kindle 系统中的 `syslog-ng.conf`，也不要使用空文件覆盖它。采集配置可能已经合并到系统日志配置中，卸载时应使用项目提供的停用流程恢复配置。

## 适用环境

- 越狱 Kindle
- Kindle 原生阅读系统
- KUAL 安装环境
- 已验证：Kindle 固件 5.17.1.0.4

## 当前版本

**v4.6.0**

## 项目地址

https://github.com/w1047865625-creator/Booktrail
