.PHONY: app run demo dump check previews install clean

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

clean:
	rm -rf .build build
