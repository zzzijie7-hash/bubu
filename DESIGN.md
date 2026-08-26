# 步步 Bubu — App 端设计规范

- **版本**: v1.0-alpha
- **平台**: iOS 17+
- **设计方向**: 草绿高亮 + 墨蓝夜幕，"点亮地图"
- **模式**: 深色优先（暗色基底 + 星光点缀）
- **参考**: iOS HIG / Claude (人性温暖) / Linear (克制纪律)

---

## 设计理念

步步是一个"情绪向"的工具 App，不是效率工具。用户在这里记录心情、标记足迹、回忆去过的地方。设计语言要在**克制（不要抢内容）**和**温暖（有人情味）**之间取平衡。

三个核心设计原则：

1. **墨蓝夜幕** — 深色背景不是死黑，而是带透气感的墨蓝夜幕，保证亮色浮得起来
2. **一种草绿就够了** — 草绿色是唯一强调色。层级靠亮度、材质和留白建立，不靠堆颜色
3. **触觉优先** — 每个可操作元素要≥44pt，反馈要清晰。手机不是网页，手指不是鼠标

---

## 色彩系统

### 品牌色

| Token | Hex | 用途 |
|-------|-----|------|
| `primary` | `#E7FF72` | 主强调色 — 去过标记、主要按钮、已点亮状态 |
| `primary-active` | `#D7F45E` | 按压态 — 按钮按下、选中态更深一点 |
| `primary-soft` | `#46591A` | 绿的低调用法 — 标签背景、非激活标记 |

### 表面层级（暗色阶梯）

| Token | Hex | 用途 |
|-------|-----|------|
| `space` | `#060816` | 最底层 — 墨蓝夜幕，不是死黑 |
| `surface-1` | `#0C1021` | 一级浮层 — 卡片、Sheet、列表行 |
| `surface-2` | `#12172B` | 二级浮层 — 弹窗、Modal、突出卡片 |
| `surface-3` | `#20263B` | 三级浮层 — hover 态（极少用） |

### 文字色

| Token | Hex | 用途 |
|-------|-----|------|
| `ink` | `#F2F5FB` | 标题、正文（冷白，衬托草绿） |
| `ink-secondary` | `#B7BED3` | 副文字、说明文字 |
| `ink-tertiary` | `#6F7894` | 占位文字、禁用态、时间戳 |
| `on-primary` | `#11150A` | 草绿色按钮上的深色文字 |

### 语义色（尽量不用）

| Token | Hex | 用途 |
|-------|-----|------|
| `visited-bad` | `#F87171` | 仅"踩雷"标记用 — 红色是很强的信号，不要溢出到别处 |
| `visited-neutral` | `#FBBF24` | "一般"标记 |

### 宇宙装饰色（非功能性）

这些颜色只出现在装饰元素中（星点、渐变、粒子），不作为 UI 功能色：

| Token | Hex | 用途 |
|-------|-----|------|
| `star-bright` | `#FFFFFF` | 最亮的星点，opacity 0.6–0.9 |
| `star-dim` | `#8E97B8` | 暗星点，带一点冷蓝灰，op 0.2–0.4 |
| `nebula-purple` | `#434A78` | 星云渐变用，仅在装饰层，op 0.03–0.08 |
| `nebula-teal` | `#7AAE7D` | 星云渐变用，op 0.03–0.08 |

### 色板使用纪律

- `primary` #E7FF72 **只用于**：去过标记、主按钮、点亮状态、选中态
- 想去标记、推荐卡片、AI 功能入口 — 用白色/灰色阶梯，不用第二强调色
- 宇宙装饰色 opacity 不超过 0.08（背景星云）和 0.6（星点），绝不喧宾夺主
- 同一屏幕上最多出现 3 种非灰色 — primary 绿 + 2 种宇宙装饰色

---

## 字体系统

### 字体族

| 角色 | 字体 | 说明 |
|------|------|------|
| **标题** | SF Pro Rounded | 更接近品牌的柔和科技感 |
| **正文** | SF Pro Text | 小字号更清晰 |
| **数字/坐标** | SF Pro (monospaced digits) | 数字对齐 |
| **特殊装饰** | SF Pro Display | 极少量装饰性大标题用 |

### 字阶

| Token | Size | Weight | Line Height | Letter | 用途 |
|-------|------|--------|-------------|--------|------|
| `title-xl` | 28pt | Bold | 1.15 | -0.5pt | Landing / 大标题 |
| `title-lg` | 22pt | Semibold | 1.2 | -0.3pt | 页面标题、卡片主标题 |
| `title-md` | 17pt | Semibold | 1.25 | 0 | Section 标题、地点名 |
| `title-sm` | 15pt | Medium | 1.3 | 0 | 列表标题、按钮文字 |
| `body` | 15pt | Regular | 1.45 | 0 | 正文、评价、心情文字 |
| `body-sm` | 13pt | Regular | 1.4 | 0 | 地址、辅助信息 |
| `caption` | 11pt | Regular | 1.3 | 0 | 时间戳、距离、计数 |
| `button` | 15pt | Medium | 1.0 | 0 | 按钮标签 |
| `tab` | 10pt | Medium | 1.2 | 0.1pt | Tab Bar 标签 |

### 字体纪律

- 标题用 SF Pro Rounded Semibold/Bold，正文保持 SF Pro Text 的清晰度
- Bold 仅用于 title-xl（28pt）最高层级标题
- 正文 body 一律 Regular 15pt，不偷加粗来强调内容
- Dynamic Type 支持：所有字号用 `.body` / `.headline` 等语义化 Font，不用固定 pt
- 数字（距离、评分、计数）用 monospaced digits，对齐更干净

---

## 间距系统

基础单位：**4pt**（iOS 标准）

| Token | Value | 用途 |
|-------|-------|------|
| `xxs` | 4pt | 图标与文字间距 |
| `xs` | 8pt | 紧凑内边距 |
| `sm` | 12pt | 列表行内间距 |
| `md` | 16pt | 标准外边距、卡片内 padding |
| `lg` | 20pt | 卡片之间间距 |
| `xl` | 24pt | Section 间距 |
| `xxl` | 32pt | 大区块间距 |

### 安全区域

- 状态栏顶部留 `safeArea.top`
- 底部 Home Indicator 留 `safeArea.bottom`（至少 34pt）
- 水平方向左右各留 16pt 作为标准外边距
- 全屏地图例外 — 地图延伸至边缘，控件 floating 留 16pt 边距

---

## 圆角

| Token | Value | 用途 |
|-------|-------|------|
| `sm` | 8pt | 小标签、Chip |
| `md` | 12pt | **标准卡片、按钮** — 最常用的圆角 |
| `lg` | 16pt | 大卡片、Sheet top |
| `xl` | 20pt | Modal、弹窗 |
| `full` | 9999pt | Pill 标签、头像 |

- 按钮用 `md`(12pt)，不用 pill。Pill 仅用于 tag/badge
- 地图上的标记点用圆形（系统 marker 已是圆的）

---

## 深度 & 阴影

暗色模式下不用物理阴影，层级靠**亮度差**区分：

| 层级 | 处理 | 用途 |
|------|------|------|
| 0 基底 | `space` #060816 | 地图画布 |
| 1 浮层 | `surface-1` #0C1021 | Sheet、卡片 |
| 2 抬升 | `surface-2` #12172B + 0.5pt `primary` 发光边 | Modal、重要弹窗 |
| 3 最高 | `surface-3` #20263B | 极少用 |

Modal 出现时背景加 `#000000` 50% 遮罩，不是毛玻璃。

---

## 宇宙装饰系统

这是步步最有辨识度的设计语言。装饰元素只出现在**背景层**，不与内容层交互。

### 星点粒子

- 放在地图画布和 Landing/Welcome 页背景
- 随机分布、微小圆点 (1–3pt)，颜色为 `star-bright` 和 `star-dim`
- 整体 opacity 不超过 0.4，个别"亮星"可达 0.7
- 不同页面星星密度不同：地图页密度低（避免干扰标记），Welcome 页密度可稍高

### 星云渐变

- 只放在 Welcome 页和 Profile 页顶部（非地图页）
- 用 `nebula-purple` 和 `nebula-teal`，opacity 0.03–0.06
- 大半径高斯模糊，不做硬边缘
- Canvas 上叠加，让人隐约感觉"深空里有东西"

### "点亮"动效

- 用户标记"去过"时，该地点标记播放微小的光晕扩散动画
- `primary` 绿色从标记中心向外扩散 2–3 圈，0.5s 内淡出
- 不夸张，不循环

### 装饰纪律

- 星点/星云**绝对不放在内容卡片内**
- 地图上的标记点本身不做星形装饰 — 用标准 map pin + 绿色区分
- "想去"标记不发光，用灰色半透明 pin — 亮的只属于"去过"
- 每种装饰元素都要能说清"它在哪、出现在哪个页面、什么时候可见"

---

## 组件规范

### 按钮

#### `button-primary`
- 背景 `primary` #E7FF72，文字 `on-primary` #11150A
- 字体 `button` (15pt Medium)，padding 12pt×24pt，圆角 `md` (12pt)
- 高度 48pt（≥44 HIG 标准）
- 按压态：背景变 `primary-active` #D7F45E

#### `button-secondary`
- 背景透明，文字 `ink` #F2F5FB，1pt `surface-3` 描边
- 其他同 button-primary

#### `button-ghost`
- 纯文字按钮，`ink-secondary`，无背景无边框
- padding 8pt×16pt，用于不重要的操作

### 卡片

#### `card-standard`
- 背景 `surface-1`，圆角 `md` (12pt)
- padding 16pt，卡片间距 `lg` (20pt)
- 不投阴影，靠背景色差区分

#### `card-elevated`
- 背景 `surface-2`，圆角 `lg` (16pt)
- 用于 Modal、底部弹出详情
- 顶部边缘加 0.5pt `primary` 微弱发光边（opacity 0.3）

#### `card-discover`（Tinder 卡片）
- 背景 `surface-1`，圆角 `lg` (16pt)
- 顶部为地点图片区（或渐变占位），下部为地点信息
- 卡片尺寸：宽度 screen - 48pt，高度约 360pt
- 右滑/左滑时卡片跟随手指，旋转量 = 偏移量/10

### 输入 & 表单

#### `input-standard`
- 背景 `surface-1`，文字 `ink`
- 圆角 `md` (12pt)，padding 12pt×16pt，高度 48pt
- 1pt `surface-3` 描边
- 聚焦：描边变 `primary`，外圈 2pt primary 15% opacity 光环

#### `input-multiline`
- 同 input-standard，但高度可变（min 80pt）
- 用于评价文字输入

### Tag / Chip

#### `chip-default`
- 背景 `surface-2`，文字 `ink-secondary`
- 字体 `caption` (11pt)，padding 4pt×10pt，圆角 `sm` (8pt)

#### `chip-selected`
- 背景 `primary-soft` #46591A，文字 `primary` #E7FF72
- 其他同 chip-default

#### `chip-status` — 地点状态标签
- "去过·推荐"：`chip-selected` 规格
- "去过·踩雷"：背景 `visited-bad` 15% op，文字 `visited-bad`
- "想去"：背景 `surface-2`，文字 `ink-secondary`
- "去过·一般"：背景 `visited-neutral` 15% op，文字 `visited-neutral`

### 地图标记

#### 地图上的绿色点 = "去过"
- 系统 map pin marker（圆形），fill `primary` #E7FF72
- 绿色标记 = 已点亮

#### 地图上的灰/半透明点 = "想去"
- 系统 map pin marker，fill `surface-2`，描边 `ink-tertiary`
- 不抢眼 = 还未点亮

#### 地图上的红色点 = "踩雷"
- 仅在"显示踩雷"开启时出现
- fill `visited-bad`，小一号（降低视觉权重）

### 底部 Tab Bar

- 背景 `surface-1`，半透明效果 `ultraThinMaterial`
- 3 个 Tab：探索(地图) / 收藏(书签) / 我的(人物)
- 选中 tab icon fill `primary`，未选中 `ink-tertiary`
- 标签字体 `tab` (10pt Medium)

### 导航栏

- 背景透明/继承当前页面背景
- 标题字体 `title-md` (17pt Semibold)
- 返回按钮用系统 chevron

---

## 页面节奏（Surface 交替）

App 不是单页的 marketing page，但大型区块之间仍然遵守交替规律：

| 页面 | 基底 | 主要浮层 |
|------|------|----------|
| 地图探索 | `space` 全屏 | 搜索栏 `surface-1`、筛选 Sheet |
| 地点详情 | `space` | 卡片 `surface-1`、打卡 Sheet `surface-2` |
| 收藏夹列表 | `space` | 列表行 `surface-1` |
| Profile/设置 | `space` | 统计卡片 `surface-1`、菜单行 |
| Onboarding | `space` + 星云 | 卡片 `surface-1` |

地图始终是 `space` 基底，非地图页可酌情加宇宙装饰（星云、星点）。

---

## 交互 & 触控

### 触控目标

- 所有可交互元素最小 **44pt×44pt**（HIG 标准）
- 按钮高度最小 **48pt**，列表行最小 **44pt**
- Tab Bar icon 区域配合 padding 确保≥44pt

### 手势

| 手势 | 场景 | 说明 |
|------|------|------|
| 左滑 | 收藏夹列表项 | 快速切换"想去→去过"状态 |
| 右滑/左滑 | Tinder 卡片 | 想去/不感兴趣 |
| 长按地图 | 任意位置 | 快速在该坐标添加地点 |
| 下拉 | 列表页 | 刷新（几乎用不到，数据是本地+CloudKit 实时同步的） |

### 反馈

- 按钮按下：0.97x scale + `primary-active` 色变，`spring(duration: 0.15)`
- 标记"去过"：光晕扩散动画 0.5s
- Sheet 弹出：系统默认 spring（不自定义）
- 列表删除：系统默认右滑删除

---

## Do's and Don'ts

### Do
- 绿色只用于"去过/已点亮"状态和主按钮 — 一种颜色，一个语义
- SF 原生字体，不要引入第三方字体
- 层级靠 `space → surface-1 → surface-2` 亮度差建立，不靠阴影
- 宇宙装饰在背景层，opacity 不超过 0.08（星云）和 0.6（星点）
- 按钮圆角一律 `md` (12pt)，pill 仅用于 tag
- 触控最小 44pt
- 地图上亮绿色 pin = 去过/已点亮

### Don't
- 不要引入第二种强调色 — 没有紫色、没有蓝色 accent
- 不要在地图页加星云装饰 — 干扰地图识别
- 不要让宇宙装饰进入内容卡片 — 卡片是纯色 `surface-1/2`
- 不要用 shadow — 暗色模式阴影看不到，靠色差
- 不要用 pill 型按钮
- 不要让星星动效循环播放 — "点亮"是一瞬间的事
- 不要在地图标记上做星形 icon — 用标准圆形 marker pin + 颜色区分

---

## Dynamic Type & 无障碍

- 所有文字用语义化 Font（`.body` / `.headline` 等），支持系统字号缩放
- 字号放大时卡片和列表行自适应高度
- 地图标记不随字号缩放（标记大小固定）
- VoiceOver：每个标记点读出"地点名 + 状态（去过/想去）+ 类别"
- 颜色不是唯一区分方式 — "去过/想去"同时用 pin 形状(实心/空心) + 颜色区分

---

## 文件组织

项目中的主题相关文件：
- `bubu/UI/Theme/BubuTheme.swift` — 颜色 Token、字体常量、Card/Button Modifier
- `bubu/UI/Theme/CosmicDecoration.swift` — 星点视图、星云渐变背景
- `bubu/UI/Components/` — 可复用组件

---

## 待定 / 待验证

- 绿色 #E7FF72 在真机暗色屏幕上的实际观感（模拟器不准，需真机验证）
- 星点密度需在真机上调 — 密度太高显脏、太低看不出来
- "点亮"扩散动画的具体参数（扩散半径、圈数、timing curve）需在设备上调
- 星云图层在不同亮度设置下的表现（iOS 有系统亮度调节，不能假设屏幕一直是满亮）
