# 素材来源

本项目的太刀模型、刀鞘、大部分招式动作和武器音效取自 CAPCOM 的 PC 版《怪物猎人：世界／冰原》（Monster Hunter: World / Iceborne）。下文的 `resources/` 指安装包内的路径，`MHW_Extracted/` 和 `blender_file/` 指开发归档内的路径。

## 模型、动作与像素图

| 成品或开发文件 | 来源与加工 |
| --- | --- |
| 刀、刀鞘，以及 `resources/gfx/isacc_longsword/` 下各招式的 `weapon_hands*.png`、`scabbard*.png` 和收刀行走图集 | 原作刀身 `swo001.mod3`、刀鞘 `saya001.mod3` 及配套材质、贴图来自 `MHW_Extracted/chunk/wp/swo/swo001/`。项目在 Blender 中重新配手、布置四向镜头、分层渲染并像素化。刀手图集同时包含以撒模型加工出的手。 |
| 招式动画、逐帧头部锚点与刀尖轨迹 | 主要动作源为冰原太刀动作文件 `hm/wp/wp03/mot/w03_00/w03_00.lmt`。开发归档保留 G0 和 G4 两版。现用动作包括直斩 101、戳刺 112、上挑 107、气刃一至三 104／106／108、大回旋 109、见切 140、突刺接登龙 170–173、特殊纳刀 306 和居合 308。项目选段、适配以撒身体、制作四向图集和 ANM2，并从动作中采样锚点。蓄力姿势使用项目编排的五个关键帧，沿用同套刀与鞘。 |
| `blade_trail*.png` 刀光 | 项目根据各招实际刀尖轨迹绘制像素光带，在游戏中按道具泪色染色。 |
| 开发用参考 | `MHW_Extracted/` 还保留猎人装备、面部等原作提取件。`blender_file/reference/` 中有用于身高和武器比例校准的猎人参考场景。`blender_file/motion_sources/`、`blender_file/output/` 中的场景、序列帧和预览沿用相应来源。动作槽号及各招所用帧段见开发归档的 `docs/ANIMATION_LIST.md`。 |

## 原版音效与游戏内混音

音源均来自本机冰原 `chunkG0.bin` 内的 `sound/wwise/Windows/`。表中列出原始 Wwise 音库和采样编号。开发归档的 `MHW_Extracted/audio/<WEM 编号>.wem` 保留这五条原始采样。游戏读取的是 `resources/sfx/longsword/` 下转换并调音后的 48 kHz、16 位单声道 WAV。

| 游戏文件 | 原版音库 | WEM 编号 | 采用方式 |
| --- | --- | ---: | --- |
| `draw.wav` | `wp_swo_001.nbnk` | 1057051735 | 铁太刀标准拔刀声，供普通出鞘和大居合出鞘使用。 |
| `hit.wav` | `cm_hitmark_epvsp.nbnk` | 132230815 | 铁太刀斩中怪物的一条原版命中采样。 |
| `gp.wav` | `wp03_swo_epvsp.nbnk` | 367971202 | 原版见切成功的金属提示音，项目也用于居合成功挡招。 |
| `helm.wav` | `wp_swo_cmn.nbnk` | 664717410 | 原版登龙终结斩，落地出刀时播放。 |
| `helm_hit.wav` | `cm_hitmark_epvsp.nbnk` | 424066194 | 从原采样 86 ms 起取刀头，提速至 1.17 倍，突出 2–6 kHz，做成 52 ms 短音，供登龙前六段命中使用。 |
| `helm_finish.wav` | `cm_hitmark_epvsp.nbnk` | 132230815、424066194 | 从已调音的 `hit.wav` 74 ms 处起取样，降速至 0.72 倍，叠加另一条采样的刀头，留 192 ms 重击与短尾，供第七段命中使用。 |

项目调整了五种音效的响度与峰值。原始采样哈希、事件映射、截取点和最终调音记录分别见开发归档 `tests/evidence/` 中 v72、v73 和 v74 的安装记录。v75 沿用 v74 音频。

## 以撒模型、图标与工具

- 以撒身体和手由本地提供的 `blender_file/ISAAC/isaac.blend` 改制，复用了原模型的网格、UV 和材质。现存材料未注明该模型的原作者与许可。右下角 32×32 太刀道具图标由用户提供，原图作者未记录。
- 游戏内角色头部、原版充能条等使用《以撒的结合》的运行时资源。开发预览里可以看到它们与太刀图层的合成效果。
- 太刀状态机、输入、伤害判定、渲染与像素刀光生成脚本由本项目实现。开发工具中 Image-to-Pixel 的 MIT 许可见 `tools/local/image-to-pixel/LICENSE`，Lua 5.3.6 的许可见 `tools/local/lua-5.3.6/doc/readme.html`。
