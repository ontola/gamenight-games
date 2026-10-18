--- Phone screens for LÖVE games (see "Phone screens" in the GameNight docs).
--- GameNight serves the page from a real directory, and a .love file is a
--- zip, so `folder` copies the page into the save directory first.
local Phone = {}

local TYPES = { html = true, htm = true, js = true, mjs = true, css = true, json = true, svg = true,
	png = true, jpg = true, jpeg = true, webp = true, woff2 = true, apk = true }

local function files(dir, prefix, out)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir .. prefix)) do
		local path = prefix .. "/" .. name
		local info = love.filesystem.getInfo(dir .. path)
		if info and info.type == "directory" then
			files(dir, path, out)
		elseif info then
			out[#out + 1] = path:sub(2)
		end
	end
	return out
end

--- Copy `source` (a folder inside the game) to the save directory and return
--- its absolute path, for `declare_companion`. Prints a warning when the page
--- would not fit a hosted room: 128 files, 512 KiB per file and 2 MiB in all
--- once base64-encoded, and only web formats with WOFF2 fonts.
function Phone.folder(source, target)
	target = target or "gamenight-phone"
	local list = files(source, "", {})
	local total = 0
	for _, path in ipairs(list) do
		local data = assert(love.filesystem.read(source .. "/" .. path))
		local encoded = math.ceil(#data / 3) * 4
		total = total + encoded
		if encoded > 512 * 1024 then
			print(("GameNight: phone file %s is %d KiB in a hosted room; the limit is 512 KiB"):format(path, math.floor(encoded / 1024)))
		end
		if not TYPES[(path:match("%.([^./]+)$") or ""):lower()] then
			print(("GameNight: hosted rooms do not serve phone file %s"):format(path))
		end
		local dir = path:match("^(.*)/[^/]+$")
		if dir then love.filesystem.createDirectory(target .. "/" .. dir) end
		love.filesystem.createDirectory(target)
		assert(love.filesystem.write(target .. "/" .. path, data))
	end
	if #list > 128 or total > 2 * 1024 * 1024 then
		print(("GameNight: the phone screen is %d files, %d KiB in a hosted room; the limit is 128 files, 2048 KiB"):format(#list, math.floor(total / 1024)))
	end
	return love.filesystem.getSaveDirectory() .. "/" .. target
end

return Phone
