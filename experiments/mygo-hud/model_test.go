package main

import (
	"slices"
	"testing"

	"github.com/egoist/mygo"
)

func TestDemoTaskProgression(t *testing.T) {
	tasks := demoTasks()
	first := tasks[0]
	tasks.advance(100)
	if !slices.Equal(tasks, demoTasks()) {
		t.Fatal("advancing an unknown task changed the fixtures")
	}
	tasks.advance(first.id)
	if got := tasks[0]; got.id != first.id || got.status != doing {
		t.Fatalf("first advance = %+v, want the same task Doing", got)
	}
	tasks.advance(first.id)
	tasks.advance(first.id)
	if !slices.Equal(tasks, demoTasks()[1:]) {
		t.Fatalf("completed task was not removed cleanly: %+v", tasks)
	}
	tasks.advance(tasks[0].id)
	if !slices.Equal(tasks, demoTasks()[2:]) {
		t.Fatalf("task initialized as Doing was not removed: %+v", tasks)
	}
	if restarted := demoTasks(); restarted[0] != first {
		t.Fatalf("new task list inherited changes: %+v", restarted)
	}
}

func TestWindowOpacity(t *testing.T) {
	cases := []struct {
		name        string
		interactive bool
		visible     bool
		inside      bool
		want        float64
	}{
		{"hidden through", false, false, true, ghostOpacity},
		{"outside through", false, true, false, ghostOpacity},
		{"inside through", false, true, true, 0},
		{"outside interactive", true, true, false, interactiveOpacity},
		{"inside interactive", true, true, true, interactiveOpacity},
		{"hidden interactive", true, false, true, interactiveOpacity},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := windowOpacity(tc.interactive, tc.visible, tc.inside); got != tc.want {
				t.Fatalf("windowOpacity() = %.2f, want %.2f", got, tc.want)
			}
		})
	}
}

func TestContainsOnSecondaryDisplay(t *testing.T) {
	bounds := mygo.Rectangle{X: -440, Y: -120, Width: 320, Height: 200}
	cases := []struct {
		point mygo.Point
		want  bool
	}{
		{mygo.Point{X: -440, Y: -120}, true},
		{mygo.Point{X: -121, Y: 79}, true},
		{mygo.Point{X: -120, Y: -120}, false},
		{mygo.Point{X: -440, Y: 80}, false},
		{mygo.Point{X: -441, Y: -120}, false},
		{mygo.Point{X: -440, Y: -121}, false},
	}
	for _, tc := range cases {
		if got := contains(bounds, tc.point); got != tc.want {
			t.Errorf("contains(%+v, %+v) = %t, want %t", bounds, tc.point, got, tc.want)
		}
	}
}
