local net = require("@lune/net")
local stdio = require("@lune/stdio")
local task = require("@lune/task")
local datetime = require("@lune/datetime")
local process = require("@lune/process")

local my_username = ""

-- this is the format for messages we need to send to the server
type ClientMessage = {
	from_username: string,
	to_username: string?,
	to_channelid: string?,
	content: string,
	reply_to_messageid: string?,
}

-- the server returns messages in this format we can use to display messages from other users
type DirectMessage = {
	messageid: string,
	authorname: string,
	recipient_username: string,
	content: string,
	timestamp: number,
}

-- slightly hacky way to clear the terminal
local function cls()
	(process.spawn or process.exec)(if process.os == "windows" then "cls" else "clear", nil, { stdio = "forward" })
end

-- sends a GET request to my server/update which should return all messages for you
local function update(last_updated: number?)
	local mess_rec = net.request {
		url = "http://67.205.186.23:8080/update",
		method = "GET",
		body = net.jsonEncode({
			username = my_username,
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

local function send_message(to_username: string, content: string)
	local message_to_send: ClientMessage = {
		from_username = my_username,
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

local last_updated = 0

my_username = stdio.prompt("text", "Your username: ")

while task.wait(0.25) do
	cls()
	local new_messages = update(last_updated)
	for _, message in new_messages do
		last_updated = message.timestamp
		local formatted_timestamp = datetime.fromUnixTimestamp(message.timestamp):formatLocalTime("%I:%M:%S")
		print(`{ message.authorname }: { message.content } (at {formatted_timestamp})`)
	end
	local send_to_username = stdio.prompt("text", "Username to send to: (hit enter twice to just update messages)")
	local message_content = stdio.prompt("text", "Message content: ")
	if send_to_username ~= "" and message_content ~= "" then
		send_message(send_to_username, message_content)
	end
end