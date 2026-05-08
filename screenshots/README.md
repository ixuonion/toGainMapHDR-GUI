# GUI 对比截图

当前仓库无法在无交互环境中可靠截取真实 macOS 窗口图像。请在本机完成以下步骤生成交付截图：

1. 切换到升级前提交并运行应用，截图保存为 `screenshots/before-main.png`。
2. 切换回当前工作区，运行 `./package.sh Release` 后打开 `build/Export/HDRConverter.app`。
3. 在浅色模式截图保存为 `screenshots/after-light.png`。
4. 在深色模式截图保存为 `screenshots/after-dark.png`。
5. 如需记录运行时依赖错误，可临时移除 app 包内任一 metallib 后截图保存为 `screenshots/runtime-warning.png`。
