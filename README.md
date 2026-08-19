# Mihomo

Omarchy 状态栏插件：mihomo 内核的控制面板。左侧导航栏 + 右侧内容页，
覆盖 **首页 / 代理 / 配置 / 连接 / 规则** 五个页面。

直接对接 mihomo 的 external controller（RESTful API），**不依赖 Clash Verge
或任何其他 GUI 客户端**。卸载 GUI、只留内核照样能用。

## 页面

| 页面 | 内容 | 涉及接口 |
|------|------|----------|
| 首页 | 当前节点（代理组 / 节点两级选择、延迟、链路）、网络设置（只读）、代理模式、流量统计 | `/version` `/configs` `/proxies` `/traffic` `/memory` |
| 代理 | 代理组列表，展开查看节点、点选切换、整组或单节点测延迟 | `/proxies` `/proxies/{name}` `/group/{name}/delay` |
| 配置 | 手写 yaml 的路径 / 统计、重载内核、打开编辑器；规则集合可手动更新 | `configinfo` `PUT /configs` `/providers/rules` |
| 连接 | 活跃连接、上下行流量、链路与命中规则，支持过滤、单条关闭、全部关闭 | `/connections` |
| 规则 | 配置文件里的全部规则，支持按域名 / 类型 / 目标过滤 | `/rules` |

写操作（切换节点、切换模式、测延迟、关闭连接、更新 provider）都是真的写到
正在运行的内核里，和其他前端看到的是同一份状态。

## 端点发现

面板从不硬编码地址。每次调用 `bin/mihomo-ctl` 时按顺序探测，第一个命中即用：

1. `~/.config/omarchy-mihomo/config` —— 手动覆盖
2. 正在运行的内核进程参数 —— `-ext-ctl` / `-ext-ctl-unix` / `-secret`
3. 该进程启动时用的 yaml —— `external-controller` / `external-controller-unix` / `secret`
4. `127.0.0.1:9090`，无 secret —— mihomo 的默认值

所以内核跑在 TCP 端口上还是 Unix socket 上、有没有 secret，插件都能自己找到。
换成独立 mihomo 之后不需要改任何配置。

想手动指定时，新建 `~/.config/omarchy-mihomo/config`：

```
endpoint = 127.0.0.1:9090
# 或者用 unix socket：
# socket = /run/mihomo/mihomo.sock
secret = your-secret
```

排查连接问题：

```bash
~/.config/omarchy/plugins/io.github.leeyiwei0305.mihomo/bin/mihomo-ctl endpoint
```

## 键盘操作

面板打开后（`Esc` 关闭，`Tab` 切到相邻面板）：

| 按键 | 作用 |
|------|------|
| `1` – `5` | 跳到 首页 / 代理 / 配置 / 连接 / 规则 |
| `←` `→` `h` `l` | 上一页 / 下一页 |
| `↑` `↓` `j` `k` | 滚动当前页 |
| `/` | 聚焦过滤框（连接、规则页） |
| `r` | 刷新当前页 |

在代理页，节点行左键点击 = 切换，右键点击 = 测这一个节点的延迟。

## 安装

```bash
git clone https://github.com/lijiawei0305-pixel/omarchy-mihomo-plugin.git
cd omarchy-mihomo-plugin
./deploy
omarchy plugin enable io.github.leeyiwei0305.mihomo
omarchy bar move io.github.leeyiwei0305.mihomo --section right
```

`./deploy` 会校验 manifest、同步到
`~/.config/omarchy/plugins/io.github.leeyiwei0305.mihomo/`，并重启 shell。
热重载偶尔不生效，重启最可靠。

## 卸载

```bash
omarchy plugin disable io.github.leeyiwei0305.mihomo
rm -rf ~/.config/omarchy/plugins/io.github.leeyiwei0305.mihomo
```

## 依赖

`curl`、`bash`。内核侧需要开启 external controller（默认就是开的）。

## 说明

- 网络设置（端口、TUN、局域网、IPv6）是**只读**的。这些要改配置文件后重载内核，
  不适合从状态栏面板随手改。
- 只有 `Selector` 类型的代理组能手动指定节点。`URLTest` / `Fallback` /
  `LoadBalance` 由内核自己决定，接口也不接受手动指定。
- 配置页对的是这份手写 yaml。节点都写在 `proxies:` 里，没有订阅拉取。
  规则集合仍可在配置页手动更新。改完文件后点「重载配置」，不用重启服务。
- 面板关闭时只保留 30 秒一次的轻量轮询；打开时才建立 `/traffic` 与 `/memory`
  的流式连接，并按当前页决定拉取什么。
