local env = require("@std/env")

_G.PROD = false

local first_arg = env.args[1]
if first_arg then
	if first_arg == "client" then
		require("./client")
	else
		require("./server")
	end
end

return nil