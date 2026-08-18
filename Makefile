SHELL := /bin/bash

APP_NAME := GhostPin

.DEFAULT_GOAL := help

.PHONY: help dev start run restart stop build test verify logs telemetry cli dmg package release

help: ## 查看常用开发命令
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

dev: start ## 构建并启动开发版 App

start: ## 构建并启动开发版 App
	@./script/build_and_run.sh run

run: start ## start 的别名

restart: ## 构建并重启开发版 App
	@./script/build_and_run.sh run

stop: ## 停止正在运行的 App
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	@echo "$(APP_NAME) 已停止（如果正在运行）"

build: ## 构建 Swift 目标
	@swift build

test: ## 运行核心行为检查
	@swift run GhostPinCoreChecks

verify: ## 构建 App 并验证可以启动
	@./script/build_and_run.sh --verify

logs: ## 启动 App 并跟踪统一日志
	@./script/build_and_run.sh --logs

telemetry: ## 启动 App 并跟踪 GhostPin subsystem 日志
	@./script/build_and_run.sh --telemetry

cli: ## 执行开发版 CLI，例如 make cli ARGS='list --json'
	@if [ -z "$(ARGS)" ]; then \
		echo "用法: make cli ARGS='list --json'" >&2; \
		exit 2; \
	fi
	@swift run ghostpin-cli $(ARGS)

dmg: ## 构建并校验 DMG
	@./script/package_dmg.sh

release: ## 发布新版本(先修改 script/VERSION 与 CHANGELOG,再执行)
	@./script/release.sh

package: dmg ## dmg 的别名
