APP_NAME := GhostPin
WINDOWS_APP_NAME := GhostPin.Windows.App
WINDOWS_SOLUTION := windows/GhostPin.Windows.sln
WINDOWS_APP_PROJECT := windows/src/GhostPin.Windows.App/GhostPin.Windows.App.csproj
WINDOWS_APP_BINARY = windows/src/GhostPin.Windows.App/bin/$(CONFIGURATION)/net10.0-windows/win-x64/$(WINDOWS_APP_NAME).exe
WINDOWS_NATIVE_ROOT := windows-native
WINDOWS_NATIVE_BUILD := $(WINDOWS_NATIVE_ROOT)/build-stage1
WINDOWS_NATIVE_EXE := $(WINDOWS_NATIVE_BUILD)/GhostPin.Native.exe
WINDOWS_NATIVE_BUILD_SCRIPT := $(WINDOWS_NATIVE_ROOT)/build_stage1.cmd

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
	@echo GhostPin Windows development commands
	@echo make dev          构建并启动原生开发版 App
	@echo make restart      构建并重启原生开发版 App
	@echo make stop         停止原生 Windows App
	@echo make build        构建 WPF 回退版 Windows App
	@echo make test         运行 WPF 回退版测试
	@echo make verify       构建、启动并验证原生 App 进程
	@echo make package      打包 WPF 回退版 Windows App
	@echo 原生构建脚本固定使用 Release；正式发布暂不包含原生客户端

start:
	@call $(WINDOWS_NATIVE_BUILD_SCRIPT)
	@powershell -NoProfile -Command "Start-Process -FilePath '$(WINDOWS_NATIVE_EXE)'"

restart: stop start

stop:
	@taskkill /IM GhostPin.Native.exe /F >NUL 2>&1 || exit /b 0
	@echo 原生 Windows App 已停止（如果正在运行）

build:
	@dotnet build $(WINDOWS_SOLUTION) --configuration $(CONFIGURATION) -p:NuGetAudit=$(NUGET_AUDIT)

test:
	@dotnet test $(WINDOWS_SOLUTION) --configuration $(CONFIGURATION) -p:NuGetAudit=$(NUGET_AUDIT)

verify: start
	@powershell -NoProfile -Command "$$deadline = (Get-Date).AddSeconds(5); do { if (Get-Process -Name 'GhostPin.Native' -ErrorAction SilentlyContinue) { exit 0 }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $$deadline); exit 1"

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
