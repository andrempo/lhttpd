local extmap = {
  txt = "text/plain",
  htm = "text/html",
  pht = "text/html",
  lua = "text/html",
  html = "text/html"
}

function executeCode (conn, code)
	-- define new print function
	local oldprint = print
	local newprint = function(...)
		for i,v in ipairs(arg) do
			conn:send(tostring(v))
		end
	end

	print = newprint
	
	-- try to compile lua code
	local luaFunc, err = loadstring(code)
	if luaFunc ~= nil then
		-- no errors -> execute
		local status, err = pcall(assert(luaFunc))
		if status == false then
			print("Runtime error: ", err )
		end
	else
		conn:send("Syntax error: " .. err)
	end
	
	-- reset print function
	print = oldprint
	newprint = nil
	oldprint = nil
	luaFunc = nil
end

function sendFile(conn, filename, params)
	if file.open(filename, "r") then
		local ftype = string.match(filename, "%.([%a%d]+)$")
		conn:send(responseHeader("200 OK", extmap[ftype or "txt"]))
		local luaCode = ""
		local startTag = false
		
		-- url parameters
		local paramCode = "get = { \[\"file\"\] = \"" .. filename .. "\""
		if params ~= nil and params ~= "" then
			params = params .. "&"
			for i in string.gmatch(params, "[^&]+") do
				local _, _, key, value = string.find(i, "(.+)=(.+)")
				paramCode = paramCode .. ", \[\"" .. key .. "\"\]=\"" .. value .. "\" "
			end
		end
		paramCode = paramCode .. "} \n"
		
		repeat
			local line = file.readline()
			if line then
				if line:find("<%?lua(.+)%?>") then
					-- single line lua code
                         print( "single line " .. getCode(line, "<%?lua(.+)%?>"))
					luaCode = paramCode .. " " .. getCode(line, "<%?lua(.+)%?>")
					executeCode(conn, luaCode)
					startTag = false
				elseif line:find("<%?lua") then
					-- multi line lua code
					luaCode = paramCode .. " " .. getCode(line, "<%?lua(.+)")
					startTag = true
				elseif line:find("%?>") then
					-- end of lua code
					luaCode = luaCode .. " " .. getCode(line, "(.+)%?>")
					-- execute lua code
					executeCode(conn, luaCode)
					startTag = false
				elseif startTag then
					luaCode = luaCode .. " " .. line
				else
					conn:send(line)
				end
			end
		until not line
		file.close()
	else
		conn:send(responseHeader("404 Not Found","text/html"))
		conn:send("Page not found")
	end
end

function getCode(str, pattern)
	local _, _, c = string.find(str, pattern)
	if c == nil then
		c = ""
	end
	return c
end

function responseHeader(code, htype)
	return "HTTP/1.1 " .. code .. "\r\nConnection: close\r\nServer: luaweb\r\nContent-Type: " .. htype .. "\r\n\r\n"
end
	
local srv = net.createServer(net.TCP) 
srv:listen(80, function(conn) 
	conn:on("receive", function(conn,payload) 
		_, _, method, req = string.find(payload, "([A-Z]+) (.+) HTTP/(%d).(%d)")
		_, _, fname, params = string.find(req, "/(.+%.[a-z]+)%??(.*)")
		--print(fname)
		--print(params)
		if fname ~= nil then
			sendFile(conn, fname, params)
		else
			sendFile(conn, "index.html", "")
		end
	end) 
	conn:on("sent",function(conn) conn:close() end)
end)
