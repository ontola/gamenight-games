local Lifecycle = {}
Lifecycle.__index = Lifecycle
function Lifecycle.new(transport, hooks, game)
	hooks.hide()
	return setmetatable({ transport = transport, hooks = hooks, game = game, phase = "idle" }, Lifecycle)
end
function Lifecycle:dispose()
	self.hooks.hide()
	self.hooks.dispose()
	self.session, self.phase, self.pending = nil, "idle", nil
end
--- Build the match a prepare asked for, once its progress report is out.
function Lifecycle:step()
	local pending = self.pending
	if not pending or self.phase ~= "preparing" then return end
	self.pending = nil
	self.hooks.prepare(pending.seats, pending.players)
	self.phase = "ready"
	if self.hooks.party then
		self.transport:send({
			type = "participation",
			session = self.session,
			instant_join = self.hooks.instantJoin == true,
		})
	end
	self.transport:send({ type = "ready", session = self.session })
end
function Lifecycle:receive(m)
	if m.type == "controller_frame" and self.hooks.input then
        self.hooks.input(m.controllers)
    elseif m.type == "welcome" then
		assert(m.protocol_version == 1, "Unsupported GameNight protocol")
        if self.hooks.settings then self.transport:send({type="declare_settings", settings=self.hooks.settings}) end
        if self.hooks.companion then
            local screen = self.hooks.companion()
            if screen then self.transport:send({type="declare_companion", root=screen.root, entry=screen.entry, app=screen.app}) end
        end
    elseif m.type == "companion_presence" and self.hooks.phonePresence then
        self.hooks.phonePresence(tostring(m.player_id or ""), m.connected == true)
    elseif m.type == "companion_message" and self.hooks.phone then
        self.hooks.phone(tostring(m.player_id or ""), m.data)
    elseif m.type == "setting_changed" and self.hooks.setting then
        self.hooks.setting(m.key, m.value)
	elseif m.type == "prepare" and m.game == self.game and m.session ~= self.session then
		self:dispose()
		self.session = m.session
		-- Say what is happening first and build the match on the next frame,
		-- so the lobby shows the loading state before the work blocks.
		self.phase = "preparing"
		self.pending = { seats = m.seats or {}, players = m.players or {} }
		self.transport:send({ type = "progress", session = self.session, percent = 20, label = "Setting up the match" })
	elseif self.session and m.session == self.session then
		if m.type == "party_updated" and self.hooks.party then
			self.hooks.party(m.seats or {}, m.players or {}, m.presence or {})
		elseif m.type == "start" and self.phase == "ready" then
			self.phase = "running"
			self.hooks.show()
		elseif m.type == "pause" and (self.phase == "running" or self.phase == "finished") then
			self.previous = self.phase
			self.phase = "paused"
			self.hooks.hide()
		elseif m.type == "resume" and self.phase == "paused" then
			self.phase = self.previous
			self.hooks.show()
		elseif m.type == "dispose" then
			self:dispose()
		end
	end
end
function Lifecycle:update()
	-- A prepare received last frame runs after this poll has sent its
	-- progress report, never in the frame that received it.
	local waiting = self.pending
	local ok, err = self.transport:poll(function(m)
		self:receive(m)
	end)
	if not ok then
		self:dispose()
		self.transport:close()
		self.hooks.quit(err)
		return
	end
	if waiting and self.pending == waiting then self:step() end
end
function Lifecycle:finish()
	if self.phase == "running" then
		self.transport:send({ type = "finished", session = self.session })
	end
end
--- Send JSON to one player's phone screen, or to every phone without `player_id`.
function Lifecycle:phone(data, player_id)
	self.transport:send({ type = "companion_message", data = data, player_id = player_id })
end
function Lifecycle:activity(controller)
	if self.phase == "running" and self.session then
		self.transport:send({ type = "controller_input", session = self.session, controller = controller })
	end
end
function Lifecycle:back()
	if self.phase == "running" or self.phase == "finished" then
		self.transport:send({ type = "request_overlay" })
	end
end
return Lifecycle
