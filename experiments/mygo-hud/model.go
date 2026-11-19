package main

import (
	"slices"

	"github.com/egoist/mygo"
)

const (
	ghostOpacity       = 0.82
	interactiveOpacity = 1.0
)

type status string

const (
	todo  status = "Todo"
	doing status = "Doing"
)

type task struct {
	id     int
	title  string
	status status
}

type taskList []task

func demoTasks() taskList {
	return taskList{
		{id: 1, title: "整理桌面验收记录", status: todo},
		{id: 2, title: "核对跨 Space 行为", status: doing},
		{id: 3, title: "试用双屏拖动", status: todo},
	}
}

func (tasks *taskList) advance(id int) {
	index := slices.IndexFunc(*tasks, func(t task) bool { return t.id == id })
	if index < 0 {
		return
	}
	if (*tasks)[index].status == todo {
		(*tasks)[index].status = doing
		return
	}
	// A second advance completes the task and removes it from the HUD.
	*tasks = slices.Delete(*tasks, index, index+1)
}

func contains(bounds mygo.Rectangle, point mygo.Point) bool {
	return point.X >= bounds.X && point.X < bounds.X+bounds.Width &&
		point.Y >= bounds.Y && point.Y < bounds.Y+bounds.Height
}

func windowOpacity(interactive, visible, pointerInside bool) float64 {
	if interactive {
		return interactiveOpacity
	}
	if visible && pointerInside {
		return 0
	}
	return ghostOpacity
}
