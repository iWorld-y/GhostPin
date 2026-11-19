package main

import (
	"flag"
	"log"
	"runtime"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

const (
	appName        = "GhostPin MyGo HUD"
	cursorInterval = 30 * time.Millisecond
)

type hud struct {
	window *mygo.Window
	tasks  taskList

	panel        bool
	focusRelease string

	visible     bool
	interactive bool
	opacity     float64
	stopCursor  chan struct{}
}

func main() {
	panel := flag.Bool("panel", false, "compare a nonactivating Panel with the default window")
	focusRelease := flag.String("focus-release", "hide-show", "return from interactive mode with hide-show or blur")
	flag.Parse()
	if *focusRelease != "hide-show" && *focusRelease != "blur" {
		log.Fatal("focus-release must be hide-show or blur")
	}
	if runtime.GOOS != "darwin" {
		log.Fatal("the MyGo HUD prototype requires a macOS desktop")
	}

	h := &hud{
		tasks:        demoTasks(),
		panel:        *panel,
		focusRelease: *focusRelease,
		opacity:      ghostOpacity,
	}
	mygo.App.SetName(appName)
	mygo.App.SetActivationPolicy(mygo.ActivationPolicyAccessory)
	mygo.App.WhenReady(h.ready)
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
}

func (h *hud) ready() {
	h.window = mygo.NewWindow(mygo.WindowOptions{
		Title:             appName,
		Width:             356,
		Height:            232,
		MinWidth:          300,
		MinHeight:         172,
		Hidden:            true,
		Frameless:         true,
		Panel:             h.panel,
		Transparent:       true,
		CornerRadius:      12,
		DisableResize:     true,
		DisableMove:       true,
		DisableMinimize:   true,
		DisableMaximize:   true,
		DisableFullScreen: true,
		DisableClose:      true,
		AlwaysOnTop:       true,
		IgnoreMouseEvents: true,
		Opacity:           h.opacity,
		Content:           ui.View(h.view),
	})
	h.window.SetVisibleOnAllWorkspaces(true)
	h.window.OnMove(h.refreshOpacity)
	h.window.OnResize(h.refreshOpacity)

	visibility := &mygo.MenuItem{Label: "显示 HUD", Click: func(_ *mygo.MenuItem, _ *mygo.Window) {
		h.setVisible(!h.visible)
	}}
	interactive := &mygo.MenuItem{
		Label: "交互模式", Type: mygo.MenuItemCheckbox,
		Click: func(item *mygo.MenuItem, _ *mygo.Window) {
			h.setInteractive(item.IsChecked())
		},
	}
	onTop := &mygo.MenuItem{
		Label: "窗口置顶", Type: mygo.MenuItemCheckbox, Checked: true,
		Click: func(item *mygo.MenuItem, _ *mygo.Window) {
			h.window.SetAlwaysOnTop(item.IsChecked())
		},
	}
	allSpaces := &mygo.MenuItem{
		Label: "跨 Space 和全屏显示", Type: mygo.MenuItemCheckbox, Checked: true,
		Click: func(item *mygo.MenuItem, _ *mygo.Window) {
			h.window.SetVisibleOnAllWorkspaces(item.IsChecked())
		},
	}
	h.window.OnShow(func() { visibility.SetLabel("隐藏 HUD") })
	h.window.OnHide(func() { visibility.SetLabel("显示 HUD") })
	tray, err := mygo.NewTray(mygo.TrayOptions{
		Title:   "MyGo HUD",
		ToolTip: appName,
		Menu: mygo.NewMenu([]*mygo.MenuItem{
			visibility, interactive, onTop, allSpaces, mygo.Separator(),
			{Label: "退出 MyGo HUD", Click: func(*mygo.MenuItem, *mygo.Window) { mygo.App.Quit() }},
		}),
	})
	if err != nil {
		log.Fatal(err)
	}
	mygo.App.OnWillQuit(func(*mygo.QuitEvent) {
		h.stopSampling()
		tray.Destroy()
	})
	h.setVisible(true)
}

func (h *hud) setVisible(visible bool) {
	h.visible = visible
	if visible {
		h.refreshOpacity()
		h.window.ShowInactive()
	} else {
		h.window.Hide()
		h.refreshOpacity()
	}
	h.syncSampling()
}

func (h *hud) setInteractive(interactive bool) {
	h.interactive = interactive
	h.window.SetIgnoreMouseEvents(!interactive)
	h.window.SetMovable(interactive)
	h.window.SetResizable(interactive)
	h.refreshOpacity()
	h.window.Invalidate()

	if interactive {
		if !h.visible {
			h.setVisible(true)
		}
		h.window.Focus()
	} else if h.visible {
		if h.focusRelease == "blur" {
			h.window.Blur()
		} else {
			h.window.Hide()
			h.window.ShowInactive()
		}
	}
	h.syncSampling()
}

func (h *hud) refreshOpacity() {
	pointerInside := false
	if h.visible && !h.interactive {
		pointerInside = contains(h.window.Bounds(), mygo.Screen.CursorScreenPoint())
	}
	opacity := windowOpacity(h.interactive, h.visible, pointerInside)
	if opacity != h.opacity {
		h.opacity = opacity
		h.window.SetOpacity(opacity)
	}
}

// Ignoring mouse events also prevents relying on the HUD's own hover events.
func (h *hud) syncSampling() {
	if !h.visible || h.interactive {
		h.stopSampling()
		return
	}
	if h.stopCursor != nil {
		return
	}

	stop := make(chan struct{})
	h.stopCursor = stop
	go func() {
		ticker := time.NewTicker(cursorInterval)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				mygo.RunOnMain(func() {
					if h.stopCursor == stop {
						h.refreshOpacity()
					}
				})
			}
		}
	}()
}

func (h *hud) stopSampling() {
	if h.stopCursor != nil {
		close(h.stopCursor)
		h.stopCursor = nil
	}
}
