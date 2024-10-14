-- make a custom lualine component
local L = require("lualine.component"):extend()

-- using plenary's curl functions to make my life so much easier
-- i could kiss you TJ DeVries
local Curl = require("plenary.curl")

-- options the spotty componenent has available to it
local default_options = {
	style = "default",
}

-- users client id & secret do need to be entered manually in order to retrieve auth token
local client_id = os.getenv("SPOTIFY_CLIENT_ID")
local client_secret = os.getenv("SPOTIFY_CLIENT_SECRET")

-- our redirect_uri
local redirect_uri = "http://localhost:8888/"
-- scopes required by spotty.nvim
local scopes = "user-read-playback-state user-read-currently-playing"

-- helper function for state query
-- https://glot.io/snippets/fumdxxarp3
local function randomStringOf(n)
	local length = math.random(10, n)
	local array = {}
	for i = 1, length do
		array[i] = string.char(math.random(55, 123))
	end
	return table.concat(array)
end

-- helper function to open a url immediately on any page
local function open_url(url)
	local open_cmd
	url = vim.fn.shellescape(url)
	if vim.fn.has("mac") == 1 then
		open_cmd = "open " .. url
	elseif vim.fn.has("unix") == 1 then
		open_cmd = "xdg-open " .. url
	elseif vim.fn.has("win32") == 1 then
		open_cmd = "start " .. url
	else
		print("Platform not supported for opening URLs")
		return
	end
	-- Execute the command
	vim.cmd("silent !" .. open_cmd)
end

-- https://neovim.io/doc/user/lua.html#_vim.uv
local function create_server(host, port, on_connect)
	local server = vim.uv.new_tcp()
	server:bind(host, port)
	server:listen(128, function(err)
		assert(not err, err) -- Check for errors.
		local sock = vim.uv.new_tcp()
		server:accept(sock) -- Accept client connection.
		on_connect(sock) -- Start reading messages.
	end)
	return server
end

local function parse_query_params(path)
	local query = {}
	local query_string = path:match("%?(.*)$")
	if query_string then
		for key, value in query_string:gmatch("([^&=?]+)=([^&=?]+)") do
			query[key] = value
		end
	end
	return query
end

-- another helper for parsing the text we recieve
local function parse_http_request(request)
	local headers = {}
	local lines = vim.split(request, "\r\n")

	-- Extract the request line (e.g., "GET /?code=123 HTTP/1.1").
	local request_line = table.remove(lines, 1)
	local method, path = request_line:match("^(%w+)%s+([^%s]+)")

	-- Process headers until we find an empty line (which separates headers from the body).
	for _, line in ipairs(lines) do
		local key, value = line:match("^(.-):%s*(.*)")
		if key and value then
			headers[key] = value
		end
	end

	return {
		method = method,
		path = path,
		headers = headers,
	}
end

local function set_cached_token(data)
	local cache_dir = vim.fn.stdpath("cache") .. "/spotty"
	local cache_file = cache_dir .. "/keys.json"

	if vim.fn.isdirectory(cache_dir) == 0 then
		return nil
	end

	local file = io.open(cache_file, "w")
	if file then
		file:write(vim.json.encode(data))
		file:close()
	end
end

-- alot of heavy lifting here
local TOKEN = nil
function RequestAccess()
	create_server("127.0.0.1", 8888, function(sock)
		local buffer = ""
		sock:read_start(function(err, chunk)
			assert(not err, err) -- Check for errors.
			if chunk then
				buffer = buffer .. chunk

				if buffer:find("\r\n\r\n") then
					-- Parse the HTTP request.
					local request = parse_http_request(buffer)
					-- ignore request for favicon
					if request.path:match("^/favicon.ico") then
						sock:close()
						return
					end

					-- Extract query parameters from the path.
					local query_params = parse_query_params(request.path)
					local code = query_params["code"]

					-- Send a response back to the browser.
					local response
					if code ~= nil or "" then
						-- the route to take if successful
						response =
							"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nAuthorization successful! You can close this tab."

						-- seperate function called to exchange our code for a token
						RequestAuthToken(code, function(autherror, data)
							if autherror then
								print("Error exchanging code. Request Status:", autherror)
							else
								TOKEN = vim.json.decode(data.body).access_token
								set_cached_token(TOKEN)
							end
						end)
					else
						response =
							"HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nAuthorization was not successful. Please try again."
					end

					sock:write(response, function()
						sock:close() -- Close the socket after responding.
					end)
				end
			else -- EOF (stream closed).
				sock:close() -- Always close handles to avoid leaks.
			end
		end)
	end)

	open_url(
		string.format(
			"https://accounts.spotify.com/authorize?response_type=%s&client_id=%s&redirect_uri=%s&scope=%s&state=%s",
			"code",
			client_id,
			redirect_uri,
			scopes,
			randomStringOf(16)
		)
	)
end

-- helper function for encoding in base64 because i didnt want to require a library for it
local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function encode_base64(data)
	return (
		(data:gsub(".", function(x)
			local r, b = "", x:byte()
			for i = 8, 1, -1 do
				r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
			end
			return r
		end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
			if #x < 6 then
				return ""
			end
			local c = 0
			for i = 1, 6 do
				c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
			end
			return b:sub(c + 1, c + 1)
		end) .. ({ "", "==", "=" })[#data % 3 + 1]
	)
end

-- callback for exchanging code -> token
function RequestAuthToken(acc_code, callbackfn)
	Curl.post("https://accounts.spotify.com/api/token", {
		body = {
			code = acc_code,
			redirect_uri = redirect_uri,
			grant_type = "authorization_code",
		},
		headers = {
			content_type = "application/x-www-form-urlencoded",
			Authorization = "Basic " .. encode_base64(client_id .. ":" .. client_secret),
		},
		callback = function(out)
			if out.status == 200 then
				return callbackfn(nil, out)
			else
				return callbackfn(out.status, nil)
			end
		end,
	})
end

-- small function that converts milliseconds into understandable min:seconds as a string
local function ms_to_time(ms)
	local minutes = math.floor((ms / 1000) / 60)
	local seconds = math.floor((ms / 1000) % 60)
	return string.format("%d:%02d", minutes, seconds)
end

-- one of the request functions
function GetTrackname()
	if TOKEN == nil then
		return "Spotty needs a token!"
	else
		vim.defer_fn(function()
			Curl.get("https://api.spotify.com/v1/me/player/currently-playing", {
				headers = {
					Authorization = "Bearer " .. TOKEN,
				},
				callback = function(out)
					if out.exit ~= 0 then
						return
					end
					-- OK status from https and correct exit code from curl
					if out.status == 200 and out.exit == 0 then
						local data = vim.json.decode(out.body)
						local play_icon
						local track_length = ms_to_time(data.progress_ms) .. " / " .. ms_to_time(data.item.duration_ms)
						if data.is_playing then
							play_icon = "󰏤"
						else
							play_icon = "󰐊"
						end
						L._statusline_ = track_length
							.. " | "
							.. play_icon
							.. " | "
							.. data.item.name
							.. " - "
							.. data.item.artists[1].name
					elseif out.status == 401 then
						L._statusline_ = "Bad Token"
					elseif out.status == 403 then
						L._statusline_ = "Bad OAuth Reqesut"
					elseif out.status == 429 then
						L._statusline_ = "Exceeded rate limits!"
					else
						L._statusline_ = "Spotify not active."
					end
				end,
			})
		end, 5000) -- delay for curl request
	end
end

local function get_cached_token()
	local cache_dir = vim.fn.stdpath("cache") .. "/spotty"
	local cache_file = cache_dir .. "/keys.json"

	if vim.fn.isdirectory(cache_dir) == 0 then
		vim.fn.mkdir(cache_dir, "p")
		return nil
	end

	if vim.fn.filereadable(cache_file) == 0 then
		local file = io.open(cache_file, "w")
		if file then
			file:write("{}") -- Initialize with an empty JSON object or any default content
			file:close()
		end
		return nil
	end

	local file = io.open(cache_file, "r")
	if file then
		local content = file:read("*a")
		file:close()
		return vim.json.decode(content)
	end
end

-- when lualine is first init
function L:init(options)
	L.super.init(self, options)
	self.options = vim.tbl_deep_extend("force", default_options, options or {})

	TOKEN = get_cached_token()

	-- where the magic happens
	if TOKEN == nil then
		RequestAccess()
	end
end

-- when update is called for every component
function L:update_status()
	return GetTrackname() or L._statusline_ or "Loading..."
end

return L
