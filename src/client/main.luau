local net = require("@lune/net")
local stdio = require("@lune/stdio")
local task = require("@lune/task")
local datetime = require("@lune/datetime")
local process = require("@lune/process")

type ClientMessage = {
	from_username: string,
	to_username: string?,
	to_channelid: string?,
	content: string,
	reply_to_messageid: string?,
}

type DirectMessage = {
	messageid: string,
	authorname: string,
	recipient_username: string,
	content: string,
	timestamp: number,
}

local function cls()
	process.exec(if process.os == "windows" then "cls" else "clear", nil, { stdio = "forward" })
end

local function send_message(to_username: string, content: string)
	local message_to_send: ClientMessage = {
		from_username = "deviaze",
		to_username = to_username,
		content = content,
	}
	local response = net.request({
		url = "http://67.205.186.23:8080/send-message",
		method = "POST",
		body = net.jsonEncode(message_to_send),
	})
	if not response.ok then
		error(response)
	end
end

local function update(last_updated: number?)
	local mess_rec = net.request {
		url = "http://67.205.186.23:8080/update",
		-- method = "POST",
		body = net.jsonEncode({
			username = "deviaze",
			last_updated = last_updated or 0,
		}),
	}
	if mess_rec.ok then
		local new_messages = net.jsonDecode(mess_rec.body)
		return new_messages :: { DirectMessage }
	else
		error(mess_rec)
	end
end

local last_updated = 0

while task.wait(0.25) do
	cls()
	local new_messages = update(last_updated)
	for _, message in new_messages do
		last_updated = message.timestamp
		local formatted_timestamp = datetime.fromUnixTimestamp(message.timestamp):formatLocalTime("%H:%M:%S")
		print(`{ message.authorname }: { message.content } (at {formatted_timestamp})`)
	end
	local send_to_username = stdio.prompt("text", "Username to send to: (hit enter twice to just update messages)")
	local message_content = stdio.prompt("text", "Message content: ")
	if send_to_username ~= "" and message_content ~= "" then
		send_message(send_to_username, message_content)
	end
end