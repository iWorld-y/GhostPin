APP_NAME := GhostPin
WINDOWS_APP_NAME := GhostPin.Windows.App
WINDOWS_SOLUTION := windows/GhostPin.Windows.sln
WINDOWS_APP_PROJECT := windows/src/GhostPin.Windows.App/GhostPin.Windows.App.csproj
WINDOWS_APP_BINARY = windows/src/GhostPin.Windows.App/bin/$(CONFIGURATION)/net10.0-windows/win-x64/$(WINDOWS_APP_NAME).exe

CONFIGURATION ?= Debug
NUGET_AUDIT ?= false

ifeq ($(OS),Windows_NT)
HOST_PLATFORM := windows
SHELL := cmd.exe
else ifeq ($(shell uname -s),Darwin)
HOST_PLATFORM := macos
SHELL := /bin/bash
else
HOST_PLATFORM := unsupported
SHELL := /bin/bash
endif

.DEFAULT_GOAL := help

.PHONY: help dev start run restart stop build test verify logs telemetry cli dmg package release

help: ## 查看当前平台的常用开发命令

dev: start ## 构建并启动开发版 App

start: ## 构建并启动开发版 App

run: start ## start 的别名

restart: ## 构建并重启开发版 App

stop: ## 停止正在运行的 App

build: ## 构建当前平台目标

test: ## 运行核心行为检查

verify: ## 构建 App 并验证可以启动

logs: ## 启动 App 并跟踪统一日志

telemetry: ## 启动 App 并跟踪 GhostPin subsystem 日志

cli: ## 执行开发版 CLI，例如 make cli ARGS='list --json'

dmg: ## 构建并校验 DMG

release: ## 发布新版本(先修改 script/VERSION 与 CHANGELOG,再执行)

ifeq ($(HOST_PLATFORM),windows)

help:
	@echo GhostPin Windows development commands - configuration: $(CONFIGURATION)
	@echo make dev          构建并启动开发版 App
	@echo make restart      构建并重启开发版 App
	@echo make stop         停止 App
	@echo make build        构建 Windows solution
	@echo make test         运行 Windows 自动测试
	@echo make verify       构建、启动并验证 App 进程
	@echo make package      打包 Windows x64 自包含单文件 EXE
	@echo 可通过 CONFIGURATION=Release 切换构建配置

start: stop
	@dotnet build $(WINDOWS_APP_PROJECT) --configuration $(CONFIGURATION) -p:NuGetAudit=$(NUGET_AUDIT)
	@powershell -NoProfile -Command "Start-Process -FilePath '$(WINDOWS_APP_BINARY)'"

restart: start

stop:
	-@taskkill /IM $(WINDOWS_APP_NAME).exe /F >NUL 2>&1
	@echo $(WINDOWS_APP_NAME) 已停止（如果正在运行）

build:
	@dotnet build $(WINDOWS_SOLUTION) --configuration $(CONFIGURATION) -p:NuGetAudit=$(NUGET_AUDIT)

test:
	@dotnet test $(WINDOWS_SOLUTION) --configuration $(CONFIGURATION) -p:NuGetAudit=$(NUGET_AUDIT)

verify: start
	@powershell -NoProfile -Command "$$deadline = (Get-Date).AddSeconds(5); do { if (Get-Process -Name '$(WINDOWS_APP_NAME)' -ErrorAction SilentlyContinue) { exit 0 }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $$deadline); exit 1"

package:
	@powershell -NoProfile -ExecutionPolicy Bypass -File script/package_windows.ps1

logs telemetry cli dmg release:
	@echo $@ 仅支持 macOS；Windows MVP 暂未提供该能力。
	@exit 2

else ifeq ($(HOST_PLATFORM),macos)

help:
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start:
	@./script/build_and_run.sh run

restart:
	@./script/build_and_run.sh run

stop:
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	@echo "$(APP_NAME) 已停止（如果正在运行）"

build:
	@swift build

test:
	@swift run GhostPinCoreChecks

verify:
	@./script/build_and_run.sh --verify

logs:
	@./script/build_and_run.sh --logs

telemetry:
	@./script/build_and_run.sh --telemetry

cli:
	@if [ -z "$(ARGS)" ]; then \
		echo "用法: make cli ARGS='list --json'" >&2; \
		exit 2; \
	fi
	@swift run ghostpin-cli $(ARGS)

dmg:
	@./script/package_dmg.sh

package: dmg ## 构建当前平台发布包

release:
	@./script/release.sh

else

help:
	@echo GhostPin 不支持在当前平台执行构建与打包，请使用 macOS 或 Windows。

build test verify package:
	@echo "错误: 当前平台不支持 GhostPin 的构建与打包。" >&2
	@exit 2

endif
