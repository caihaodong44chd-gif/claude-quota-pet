.PHONY: app run demo dump check previews install release clean

APP := build/QuotaPet.app

# 打包成 build/QuotaPet.app
app:
	./scripts/build-app.sh

# 打包并启动（先关掉正在运行的）
run: app
	-pkill -x QuotaPet
	open $(APP)

# 演示模式：假数据，75 秒看完宠物的所有状态
demo: app
	-pkill -x QuotaPet
	open $(APP) --args --demo

# 在终端打印当前额度（和 usage_lab.py 对账用）
dump:
	swift run -c release QuotaPet --dump

# 自检
check:
	swift run QuotaPetChecks

# 把宠物、菜单栏、面板渲染成 PNG 到 build/previews
previews:
	swift run -c release QuotaPet --render-previews build/previews

# 装到 ~/Applications 并打开「开机自动启动」：以后一打开 Claude 宠物就会出现
install: app
	-pkill -x QuotaPet
	mkdir -p ~/Applications
	rm -rf ~/Applications/QuotaPet.app
	cp -R $(APP) ~/Applications/
	open ~/Applications/QuotaPet.app --args --enable-login-item

# 发 GitHub Release 用：Apple 芯片 + Intel 通用版，压成 build/QuotaPet-<版本>.zip（版本号取 Info.plist）
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
# 打完包先查一遍：包里不能有本机绝对路径（仓库是公开的，Release 谁都能下载）
release:
	UNIVERSAL=1 ./scripts/build-app.sh
	@if grep -r -a -l "/Users/" $(APP); then echo "❌ 包里有本机绝对路径（上面列出的文件），不能发布"; exit 1; fi
	rm -f build/QuotaPet-$(VERSION).zip
	ditto -c -k --norsrc --noextattr --keepParent $(APP) build/QuotaPet-$(VERSION).zip
	shasum -a 256 build/QuotaPet-$(VERSION).zip

clean:
	rm -rf .build build
