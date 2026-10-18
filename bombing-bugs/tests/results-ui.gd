extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.menu_open = false; game.overlay.hide(); game.active = true; game.countdown = 0
	for cell in game.sim.cells:
		if game.sim.inside(cell) and (cell.x%2 != 0 or cell.y%2 != 0): game.sim.cells[cell] = 0
	for i in game.sim.bugs.size():
		var p = game.sim.bugs[i]
		p.name = ["Ladybug", "Nibbles", "Buzz", "Bean"][i]
		p.capacity = i+1; p.range = i+2
	game._update_badges()
	for i in game.sim.bugs.size():
		var stats = game.badges.get_child(i).get_child(1)
		assert(stats.get_child(1).text == str(i+1))
		assert(stats.get_child(3).text == str(i+2))
	game.sim.pickups[Vector2i(5,7)] = {"kind":"capacity","wait":0}
	game.sim.pickups[Vector2i(7,7)] = {"kind":"range","wait":0}
	game.garden.reset(game.sim); game.garden.sync(game.sim,.016)
	var render := "--render" in OS.get_cmdline_user_args()
	var output := "user://ui-preview"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if render: DirAccess.make_dir_recursive_absolute(output)
	if render:
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("powerups-ui.png"))
	for i in range(1,game.sim.bugs.size()): game.sim.bugs[i].alive = false
	game.sim.step(.016,[])
	assert(game.sim.ended)
	game.banner.text = "Ladybug wins!"; game._update_badges()
	var c: Vector2i = game.sim.spawns()[0]
	game.sim.bombs.append({"id":999,"cell":c,"owner":0,"range":2,"time":.05,"passers":[],"slide":Vector2i.ZERO,"glide":0.0})
	game._physics_process(.1)
	assert(game.sim.flames.size() > 0 and game.sim.flames[0].time < .65, "Main results branch must keep stepping the simulation")
	assert(game.garden.blast_views.size() > 0, "Main results branch must keep rendering effects")
	if render:
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("win-ui.png"))
		game._open_menu(false)
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("options-ui.png"))
	game._open_menu(false); game._close_menu()
	assert(game.banner.text == "Ladybug wins!", "Resume must restore the result banner")
	print("PASS player power-up HUD and running result simulation/effects")
	quit()
