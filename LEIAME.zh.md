<!-- doc: tipo=capa autoridade=pitch -->

# Il —— 自由个体化

*English: [`README.md`](README.md) · Português: [`LEIAME.md`](LEIAME.md)*

**Il**（*自由个体化*）是一个通过**自由技术**来**成为自己**的项目 —— 它的建造方式，
使得没有任何帝国、平台或守门人掌握你的文化、记忆或工具的钥匙。

它最初的果实是 **Bolha**（气泡），一种确定性的文件格式：把媒体（文本、图像、视频、
音频）聚合与引用起来，同时携带**每个组件的使用许可**。

## 为什么这重要

大多数格式把许可当作元数据 —— 一个可以忽略的标签。Bolha 让许可成为**结构性的**：
不声明一个组件可以被如何使用，就无法引用它；而同一套机制可以从内容扩展到程序和
服务。

- **许可本身就是一个 bolha** —— 或者状态 `reservado`（刻意不授予任何权利）。
  许可 bolha 指向一个**真实的目录** —— 内容用 Creative Commons，程序用 SPDX ——
  因此系统从不自己发明法律条款，也不存在一份会与事实漂移的散文文档。
- **始终按内容寻址** —— 每一个引用都是一个 sha256。bolha 是它各部分的确定性宣言；
  渲染只是副产物。
- **手与判官** —— 马具（`arreio/Arreio.lean`）写出宣言；同一套 **Lean 4** 代码库
  也存放判官，它证明*形式*；由人来确认*事实*。

## 本地循环（没有 CI 运行器）

这条链**只定义一次**，在 `cadeia/Cadeia.lean` 里，由你手上有哪台机器来运行。
GitHub Actions 不属于这个设计 —— 它曾是一个可能的运行器，从来不是源头。

    lean --run cadeia/Cadeia.lean --etapa tudo      # 整条链：判官 + 散文
    lean --run cadeia/Cadeia.lean --etapa juiz      # 只有判官
    lean --run cadeia/Cadeia.lean --etapa prosa     # 只有散文

每次运行都会写出 `recibo-<etapa>.txt`：结果、机器、分支、提交和 UTC 时间。一个
孤零零的数字说不清它从哪里来；回执说得清。回执与证明都是**生成的 —— 从不纳入版本
控制**。

门是 `.githooks/pre-push`。每个克隆启用一次：

    git config core.hooksPath .githooks

编译整个马具需要大约半分钟。`arreio/Correr.lean` 就是为此存在的：它导入已经编译好的
`.olean`，而不重新构建，代价只是零头。

## 形式住在判官里（见 `juiz/`）

规格是可执行的，不是散文：

- `juiz/Bolha.lean` —— 抽象的有效 bolha：按哈希寻址，许可永远显式。
- `juiz/Ponte.lean` —— 桥：把真实的宣言与一组 bolha 对照检查。

## 什么住在哪里

- `juiz/` —— Lean 4 里的规格（抽象 + 通往真实宣言的桥）。
- `arreio/` —— 马具，用 Lean 4 写：从真实目录创建许可 bolha，按哈希导入内容，并
  承载**音乐流程** —— 一个歌词文件进去，带编号的 `parte` bolha 和 `musica` bolha
  出来。
- `higiene/` —— 散文判官，用 Lean 4 写：每个文档声明自己的类型与权威，被引用的路径
  必须存在，而只有封面住在根目录。
- `cadeia/` —— 这条链，定义一次，任何机器都能运行。
- `ferramentas/` —— **遗产**，来自 Python/JS 周期。链上没有任何程序调用这里的东西。
  其中一部分已被 `juiz/Bolha.lean` 取代；另一部分仍然保存着从未被移植的能力，而在
  那种情况下，这个文件是唯一存在的记录。
- `.githooks/pre-push` —— **门**。这条链在每次推送之前、在你自己的机器上、本地运行。
  这里没有 GitHub Actions：证明住在它被生产出来的地方。

## 状态

早期原型。判官已在本地用 Lean 4.34.0 验证通过（`exit 0`），版本固定在 `lean-toolchain`。
没有 CI 运行器：这条链在你有的那台机器上运行。

## 两个仓库

- **Il**（这个）—— 公开的 pindorama：产品。代码先在这里诞生。
- **IltS** —— 私人的工作室（一个分叉）：日记、计划和个人内容。它从这里拉取，从不推回。

## 许可

AGPL-3.0 —— 见 `LICENSE`。
