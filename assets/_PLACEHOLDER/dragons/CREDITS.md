# 占位龙模型来源与授权记录

## Dragon2.glb（驯龙系统 · 首只巨龙「黑曜龙」占位皮）

- **作者**：bocdagla（sketchfab 作者名）
- **来源**：`dragon-assets/poc/bocdagla/upload/Dragon2.glb`（2026-10-01 由资产复核线下载留档，
  原始 zip 内无 LICENSE 文件；作者自述许可为 **Creative Commons Attribution（未标版本号）**——
  授权结论以 `dragon-assets/poc/REPORT.md` §7.2 的复核记录为准，**不得擅自改写为 "CC BY 4.0"**）
- **入库**：2026-10-02 复制到本目录（字节一致，sha256 `eefbbb611e07ae64f46634dd4c260cafcae9afbc78e316c327a692aabe6149e1`）
- **技术要点**（详见 `dragon-assets/poc/REPORT.md`）：
  - 2,004 三角面 / 76 骨骼 / 1 材质（内嵌 4×4 调色板贴图，自包含单文件）；
  - 六条动画：`Idle_loop` / `Walk_menacing_loop` / `Attack` / `AttackPose` / `GroundToFly` / `Flying_loop`；
  - 模型自身朝 **+Z**（头在 +Z、尾在 −Z）→ `model_face_offset_deg = 180`；
  - **静态 AABB（10.45 高）比实际渲染（约 5.68 单位）大 1.84×**——缩放与血条高度一律按
    实渲口径配置，不要按 AABB 反推（报告 §3 实测）。
