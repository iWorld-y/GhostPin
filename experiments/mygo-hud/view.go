package main

import "github.com/egoist/mygo/ui"

func (h *hud) view(c *ui.Context) {
	c.Root().Background(ui.Transparent)
	ui.Column(c).Fill().Radius(12).Background(ui.RGBA(24, 27, 34, 0.90)).Children(func() {
		header := ui.Row(c).FillWidth().Height(38).PaddingX(12).Gap(10)
		if h.interactive {
			header.DragWindow()
		}
		header.Children(func() {
			ui.Text(c, "MyGo HUD").Grow(1).Bold().FontSize(14).TextColor(ui.Hex("#f1f3f7"))
			mode := "穿透"
			if h.interactive {
				mode = "交互"
			}
			ui.Text(c, mode).FontSize(12).TextColor(ui.Hex("#b7c2d5"))
		})
		ui.Scroll(c).FillWidth().Grow(1).PaddingX(12).Gap(5).Children(func() {
			if len(h.tasks) == 0 {
				ui.Text(c, "演示任务已完成").PaddingY(8).FontSize(13).TextColor(ui.Hex("#b7c2d5"))
			}
			for _, task := range h.tasks {
				h.taskRow(c.Key(task.id), task)
			}
		})
		if h.interactive {
			ui.Text(c, "Tab 选中 · 空格推进 · 拖动窗口边缘缩放").FontSize(11).
				Padding(8, 12).TextColor(ui.Hex("#b7c2d5"))
		} else {
			ui.Spacer(c).Height(8).Grow(0)
		}
	})
}

func (h *hud) taskRow(c *ui.Context, task task) {
	ui.Row(c).FillWidth().MinHeight(38).Gap(8).Padding(4, 6).Radius(6).
		Background(ui.RGBA(255, 255, 255, 0.08)).Children(func() {
		statusColor, action := ui.Hex("#cadeff"), "开始"
		if task.status == doing {
			statusColor, action = ui.Hex("#ffd487"), "完成"
		}
		ui.Text(c, string(task.status)).Width(42).NoWrap().FontSize(11).TextColor(statusColor)
		ui.Text(c, task.title).Grow(1).MinWidth(0).NoWrap().FontSize(13).TextColor(ui.Hex("#f1f3f7"))
		ui.Button(c.Key("advance"), action).Label(action + " " + task.title).
			Disabled(!h.interactive).FocusRing(true).OnClick(func() {
			if h.interactive {
				h.tasks.advance(task.id)
			}
		})
	})
}
