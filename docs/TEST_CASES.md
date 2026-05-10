# 测试用例：face-swap-video

## 1. 安全与授权测试

| ID | 用例 | 输入 | 预期 |
|---|---|---|---|
| S001 | 缺少授权清单 | config 无 consent_manifest | 拒绝执行 |
| S002 | 源人脸未授权 | source_face 不在 source_faces | 拒绝执行 |
| S003 | 目标视频未授权 | target_video 不在 target_videos | 拒绝执行 |
| S004 | 授权用途不匹配 | allowed_use 不含 face_swap_test | 拒绝执行 |
| S005 | 关闭水印 | watermark_text 为空 | 默认拒绝，除非显式测试模式 |
| S006 | 授权过期 | expires_at 小于当前日期 | 拒绝执行 |

## 2. 配置测试

| ID | 用例 | 输入 | 预期 |
|---|---|---|---|
| C001 | 读取合法配置 | 完整 JSON | 返回 PipelineConfig |
| C002 | 缺少 source_face | JSON 缺字段 | 抛出配置错误 |
| C003 | 缺少 output_dir | JSON 缺字段 | 抛出配置错误 |
| C004 | 相对路径规范化 | 相对路径 | 相对于配置文件目录解析 |

## 3. CLI 测试

| ID | 用例 | 命令 | 预期 |
|---|---|---|---|
| CLI001 | help | `python -m face_swap_video --help` | 输出帮助 |
| CLI002 | dry-run 成功 | 合法 config | exit code 0 |
| CLI003 | dry-run 失败 | 未授权 config | exit code 非 0 |

## 4. 后续集成测试

| ID | 用例 | 预期 |
|---|---|---|
| V001 | 单人脸短视频检测 | 检出稳定 face track |
| V002 | 多人脸视频检测 | 能区分多个 track |
| V003 | 低置信度跳过 | 不强行换脸 |
| V004 | 输出水印 | 输出视频可见水印 |
| V005 | 报告生成 | report.json 包含素材 hash 和参数 |
