# 验证记录

[← README](README.md) · [文档](docs/README.md)

---

版本：**2.5.3 (45)**

日期：**2026-09-10**

## 测试

Xcode 26.4，Intel macOS 26.3。完整测试 161 项，159 项通过、2 项按需审计跳过，0 项失败。跳过项为 CPU 长测和 Tibo 公共源在线审计，不影响常规回归。

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

## 本版覆盖

- 相同实时快照重复应用 30 次，不产生额外状态发布；任务变化、切换、删除与恢复仍会更新
- 窗口收起后继续读取 Token 事件；重新展开保留视图状态
- 菜单栏文字随用量变化更新，图标在指标不变时复用
- 滚动文字在中日韩、拉丁字符及数字下保留字形和行高
- Tibo 公布、确认、待确认、低概率、空数据与离线状态，以及重置时区解析
- 七种语言的版本日志、浅深色页面、固定高度与页脚边界

## 窗口

- 毛玻璃背景和内容使用相同的 14pt 圆角；原生遮罩同时约束窗口阴影
- 圆角遮罩在 340 × 680、340 × 480 和 420 × 680pt、1× / 2× 下检查了四角像素
- 浅色、深色和高对比度外观保留原生菜单材质
- 屏幕边界、主题切换和页面切换的窗口稳定性检查通过

以上为原生视图属性与渲染验证。减少透明度、macOS 14 真机运行和实机桌面合成仍未验证。

## 分发

[GitHub Release v2.5.3](https://github.com/Lincb522/CodexLens/releases/tag/v2.5.3) · [发布工作流](https://github.com/Lincb522/CodexLens/actions/workflows/release.yml)

`v*` tag 工作流运行完整测试，再生成 arm64 / x86_64 通用架构 DMG、ZIP、SHA-256 清单和 Sparkle 更新源。安装包使用 Developer ID 签名，tag 发布不提交 Apple 公证；具体状态见对应发布页。

下载后可验证：

```bash
shasum -a 256 -c SHA256SUMS.txt
unzip -t Codex-Lens-macOS.zip
hdiutil verify Codex-Lens-macOS.dmg
codesign --verify --deep --strict --verbose=2 "Codex Lens.app"
lipo -archs "Codex Lens.app/Contents/MacOS/Codex Lens"
```
