function love.conf(t)
	t.identity = "gamenight-hexstead"
	t.version = "11.5"
	t.window.title = "Hexstead"
	t.window.width, t.window.height = 1280, 760
	t.window.resizable, t.window.vsync = true, 1
	t.window.highdpi = true
	if os.getenv("HEXSTEAD_TEST") == "1" then
		t.window = false
		t.modules.graphics, t.modules.audio, t.modules.sound = false, false, false
	end
end
