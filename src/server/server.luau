--!strict

-- this runs on my server, u don't run this on the client!!

local net = require("@lune/net")
local datetime = require("@lune/datetime")

-- type of message bodies we receive from the client
type ClientMessage = {
	from_username: string,
	to_username: string?,
	to_channelid: string?,
	content: string,
	reply_to_messageid: string?,
}

-- types of messages we store here on the server
type DirectMessage = {
	messageid: string,
	authorname: string,
	recipient_username: string,
	content: string,
	timestamp: number,
}

type ChannelMessage = {
	messageid: string,
	authorname: string,
	channelid: string,
	content: string,
	timestamp: number,
}

type UpdateInfo = {
	username: string,
	last_updated: number,
}

type ServerMessage = ChannelMessage | DirectMessage

local Messages: { [string]: DirectMessage } = {}

net.serve(8080, {
	address = "0.0.0.0",
	handleRequest = function(request)
		print(request.path)
		if request.path == "/send-message" and request.method == "POST" then
			local client_message: ClientMessage = net.jsonDecode(request.body)
			local message_timestamp = datetime.now().unixTimestamp
			local messageid = tostring(os.clock())

			if client_message.to_username then
				-- this is a direct message
				local direct_message: DirectMessage = {
					messageid = messageid,
					authorname = client_message.from_username,
					recipient_username = client_message.to_username,
					content = client_message.content,
					timestamp = message_timestamp,
				}
				Messages[messageid] = direct_message
				return net.jsonEncode(direct_message)
			elseif client_message.to_channelid then
				local channel_message: ChannelMessage = {
					messageid = messageid,
					authorname = client_message.from_username,
					channelid = client_message.to_channelid,
					content = client_message.content,
					timestamp = datetime.now().unixTimestamp
				}
				Messages[messageid] = channel_message
				return net.jsonEncode(channel_message)
			else
				error("hey, we have a client not passing .to_username or .to_channelid")
			end
		elseif request.path == "/update" then
			local messages_to_give_user: { DirectMessage } = {}
			local update_info: UpdateInfo = net.jsonDecode(request.body)

			for messageid, message: DirectMessage in Messages do 
				if message.recipient_username == update_info.username then
					table.insert(messages_to_give_user, message)
				end
			end
			table.sort(messages_to_give_user, function(a, b)
				return a.timestamp < b.timestamp
			end)
			return net.jsonEncode(messages_to_give_user)
		else
			print(request)
			return "unsupported path"
		end
	end
})


-- listen to all incoming requests from clients