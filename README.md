# 气泡音（SodaNative）

## 0.1.1 修复（2026-10-28）

- 页面切换、退出扫码页等正常请求取消，不再显示 `cancelled` 弹窗。
- 忽略过期搜索和播放请求的结果，避免快速操作后旧结果覆盖新选择。
- 空的加密字段不再误判为受保护音频；真正加密的音源仍无法在此版本播放。
- 已登录时取播放信息使用账号 ticket-guard 凭证，不再只传公共客户端令牌；该路径需真机验证，不代表已支持加密音频。
- 构建流程加入取消处理和音源标记识别的回归检查。
- 0.1.0 已通过 macOS Actions 编译；用户真机反馈确认能进入应用并登录，完整播放仍未实现。

一个供个人测试的非官方 iOS 汽水音乐客户端工程。界面参考 Kumone 的简洁布局；使用 SwiftUI 原生 TabView 和系统底部附件，在 iOS 26 及更新版本显示系统 Liquid Glass 导航与迷你播放器。

## 当前实现

- 原生五栏界面：推荐、精选、漫游、我的、搜索。
- 汽水车机接口搜索、歌曲详情与未加密音源播放。
- 抖音扫码登录流程，账号凭证保存在 iOS Keychain。
- 登录后的歌单与“我喜欢的音乐”读取。
- 后台音频与控制中心播放、暂停；仅提供受保护音源时提示并可打开官方汽水音乐。
- GitHub Actions 在 macOS 上生成未签名 IPA。

## 已核对与尚待验证

已通过公开接口测试：客户端令牌、搜索、歌曲详情、抖音二维码生成。尚未在 Xcode 中编译，也未用真实账号完成扫码确认及歌单读取。当前工作环境是 Windows，没有 Xcode；运行和安装状态必须以 GitHub Actions 构建及 iPhone 实测为准。

**当前工程不能等同官方汽水音乐。**实际测试中，一首公开搜索到的歌曲只返回加密完整音源，没有试听源。此类歌曲无法在本客户端播放。完整受保护音频要求官方客户端逐请求签名和音频解密；本工程没有这些能力，也不会把失败伪装为可播放。推荐、精选和漫游页目前使用不同搜索词展示公开歌曲，尚非汽水的个性化推荐流。下载、歌词、完整歌单管理仍待实现。

## 构建

将本目录下所有文件按原有目录结构放入 GitHub 仓库根目录。打开仓库 Actions 页，运行 **Build iOS IPA**；构建通过后，在该次运行的 Artifacts 下载 `SodaNative-unsigned-ipa`。IPA 未签名，需要由 AltStore、SideStore 或 Sideloadly 使用自己的 Apple ID 签名后安装。

开发者在 Mac 上也可以运行：

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project SodaNative.xcodeproj -scheme SodaNative -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 来源

- 界面与 IPA 打包方式参考 [Kumone](https://github.com/missuo/kumone)；未复制其代码或素材。
- 汽水车机协议、扫码登录参数和公开播放行为参考 [qishui-music-api](https://github.com/GSQZ/qishui-music-api)（MIT）。
- 受保护音源限制参见 [libresoda 的实测说明](https://github.com/sodahub-org/libresoda/blob/main/docs/FULL-QUALITY-STREAM.md)。
- 本项目与抖音、汽水音乐及上述开源项目均无隶属关系。
