# 验证记录

[← README](README.md) · [文档](docs/README.md)

---

版本：**2.5.2 (44)**

日期：**2026-09-07**

## 测试

Xcode 26.4，运行环境为 Intel macOS 26.3。窗口相关的 5 项回归测试通过，0 项失败。

```bash
xcodegen generate
xcodebuild test \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS'
```

完整测试由发布工作流执行，结果见对应运行记录。

## 窗口

- 毛玻璃背景和内容使用相同的 14pt 圆角；原生遮罩同时约束窗口阴影
- 圆角遮罩在 340 × 680、340 × 480 和 420 × 680pt、1× / 2× 下检查了四角像素
- 浅色、深色和高对比度外观保留原生菜单材质
- 屏幕边界、主题切换和页面切换的窗口稳定性检查通过

以上为原生视图属性与遮罩渲染验证，不代表实机桌面合成已验证。减少透明度、macOS 14 运行和实机四角效果仍待确认。

## 分发

[GitHub Release v2.5.2](https://github.com/Lincb522/CodexLens/releases/tag/v2.5.2) · [发布工作流](https://github.com/Lincb522/CodexLens/actions/workflows/release.yml)

`v*` tag 工作流测试后生成通用架构 DMG、ZIP、SHA-256 清单和 Sparkle 更新源。安装包使用 Developer ID 签名，tag 发布不提交 Apple 公证；具体状态见对应发布页。

下载后可验证：

```bash
shasum -a 256 -c SHA256SUMS.txt
unzip -t Codex-Lens-macOS.zip
hdiutil verify Codex-Lens-macOS.dmg
codesign --verify --deep --strict --verbose=2 "Codex Lens.app"
lipo -archs "Codex Lens.app/Contents/MacOS/Codex Lens"
```
