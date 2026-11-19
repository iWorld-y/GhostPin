package main

import (
	"slices"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestHUDAdvancesWithClickAndKeyboard(t *testing.T) {
	h := &hud{tasks: demoTasks(), interactive: true}
	view := ui.NewTester(h.view, 356, 232)
	title := h.tasks[0].title

	if err := view.Click("开始 " + title); err != nil {
		t.Fatal(err)
	}
	if got := h.tasks[0].status; got != doing {
		t.Fatalf("click changed task status to %q, want Doing", got)
	}

	button := "完成 " + title
	if !view.Focused(button) {
		view.Key(0, ui.KeyTab)
	}
	if !view.Focused(button) {
		t.Fatalf("keyboard focus did not reach %q", button)
	}
	view.Key(0, ui.KeySpace)
	if slices.Contains(view.Texts(), title) || len(h.tasks) != 2 {
		t.Fatalf("keyboard activation left the completed task in the HUD: %+v", h.tasks)
	}
}

func TestHUDDisablesTaskInputInPassThroughMode(t *testing.T) {
	h := &hud{tasks: demoTasks()}
	view := ui.NewTester(h.view, 356, 232)
	box, ok := view.Find("开始 " + h.tasks[0].title)
	if !ok {
		t.Fatal("the task button should still be displayed")
	}
	view.ClickAt(box.X+box.W/2, box.Y+box.H/2)
	view.Key(0, ui.KeyTab)
	view.Key(0, ui.KeySpace)
	if !slices.Equal(h.tasks, demoTasks()) {
		t.Fatalf("pass-through controls changed tasks: %+v", h.tasks)
	}
}
