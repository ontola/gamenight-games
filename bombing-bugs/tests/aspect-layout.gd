extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var round_index: int = game.round_index
	var initial_cells: Dictionary = game.sim.cells.duplicate()
	for physical: Vector2i in [Vector2i(960,540),Vector2i(800,600),Vector2i(1120,480),Vector2i(390,844),Vector2i(896,384),Vector2i(960,540)]:
		root.size = physical
		for frame in 4: await process_frame
		var screen: Rect2 = root.get_visible_rect()
		var aspect := float(physical.x)/physical.y
		check(absf(screen.size.x/screen.size.y-aspect) < .01,"Viewport aspect at %s" % physical)
		var contents := screen.grow(1.0)
		check(contents.encloses(game.overlay.get_global_rect()),"Start menu at %s" % physical)
		check(contents.encloses(game.title_card.get_global_rect()),"Countdown art at %s" % physical)
		check(absf(game.title_card.get_global_rect().get_center().x-screen.get_center().x)<1,"Intro centered at %s" % physical)
		var badges: GridContainer = game.badges
		check(badges.get_child_count()==4,"Four player cards at %s" % physical)
		check(badges.columns==(2 if screen.size.x<1000 else 4),"Player card columns at %s" % physical)
		for badge: Control in badges.get_children():
			check(contents.encloses(badge.get_global_rect()),"Player card bounds at %s" % physical)
		check(contents.encloses(game.banner.get_global_rect()),"Round banner at %s" % physical)
		check(badges.get_global_rect().end.y<=game.banner.get_global_rect().position.y,"Player cards overlap banner at %s" % physical)
		for x: int in [1,game.sim.w-2]:
			for y: int in [1,game.sim.h-2]:
				for height: float in [0.0,.8]:
					var corner: Vector3 = game.garden.world(Vector2(x,y))+Vector3.UP*height
					check(screen.has_point(game.camera.unproject_position(corner)),"Board corner at %s" % physical)
		var more: Button = game.menu_rows.back()
		check(contents.encloses(more.get_global_rect()),"More options reachable at %s" % physical)
		game._menu_action(game.menu_rows.size()-1,1)
		for frame in 2: await process_frame
		check(game.menu_page=="advanced","Advanced menu opens")
		for row: Button in game.menu_rows:
			check(contents.encloses(row.get_global_rect()),"Advanced menu action at %s" % physical)
		game._menu_action(game.menu_rows.size()-1,1)
		check(game.menu_page=="main","Back returns to main menu at %s" % physical)
		check(game.round_index==round_index and game.sim.cells==initial_cells,"Resize restarted the round at %s" % physical)
		print(physical," canvas ",screen.size," board camera size ",game.camera.size)
	game.sim.winner = game.sim.bugs[0].team
	game._cut_to_winner()
	var normal_fov: float = game.camera.fov
	root.size = Vector2i(1120,480)
	for frame in 4: await process_frame
	check(game.closeup>=0 and game.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"Resizing kept the winner close-up")
	check(game.camera.fov>normal_fov,"Ultrawide close-up protects vertical framing")
	root.size = Vector2i(390,844)
	for frame in 4: await process_frame
	check(is_equal_approx(game.camera.fov,normal_fov),"Portrait close-up keeps the winner's horizontal framing")
	if failures==0: print("PASS responsive menu, camera, four player cards and winner framing")
	quit(1 if failures else 0)
