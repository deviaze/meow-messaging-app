--!strict
-- rewrite with zune to fix scheduler bug

local net = require("@zcore/net")
local json = require("@zcore/serde").json
local datetime = require("@zcore/datetime")

-- Represents the JSON message format we receive from clients from POST /send-message
type ClientMessage = {
	from_username: string,
	to_username: string?,
	to_channelid: string?,
	content: string,
	reply_to_messageid: string?,
}

-- Represents a direct message we store on the server
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

type ConnectionInfo = {
	username: string,
	pin: string,
}

type UserInfo = {
	username: string,
	pin: string,
	last_updated: number,
}

type ServerMessage = ChannelMessage | DirectMessage

-- dictionary of client usernames to last update timestamps
local CurrentClients: { [string]: UserInfo } = {}

local DirectMessages: { [string]: DirectMessage } = {}

net.serve({
	address = "0.0.0.0",
	port = 8080,
	request = function(request: net.ServerRequest)
		if request.path == "/send-message" then
			local client_message: ClientMessage = json.decode(request.body)
			if request.method ~= "POST" then
				local error_response: net.ServerResponse = {
					statusCode = 405, -- method not allowed
					body = `/send-message expects POST method, got: {request.method}`
				}
				return error_response
			end
			
			local message_timestamp = datetime.now().unixTimestamp
			local messageid = tostring(os.clock())

			CurrentClients[client_message.from_username] = {
				username = client_message.from_username,
				pin = client_message.pin,
				last_updated = message_timestamp,
			}

			if client_message.to_username then
				-- this is a direct message
				local direct_message: DirectMessage = {
					messageid = messageid,
					authorname = client_message.from_username,
					recipient_username = client_message.to_username,
					content = client_message.content,
					timestamp = message_timestamp,
				}
				DirectMessages[messageid] = direct_message
				return json.encode(direct_message)
			elseif client_message.to_channelid then
				local channel_message: ChannelMessage = {
					messageid = messageid,
					authorname = client_message.from_username,
					channelid = client_message.to_channelid,
					content = client_message.content,
					timestamp = message_timestamp
				}
				-- Messages[messageid] = channel_message
				return json.encode(channel_message)
			else
				error("hey, we have a client not passing .to_username or .to_channelid")
			end
		elseif request.path == "/update" then
			local messages_to_give_user: { DirectMessage } = {}
			local update_info: UpdateInfo = json.decode(request.body)

			CurrentClients[update_info.username] = datetime.now().unixTimestamp

			for messageid, message: DirectMessage in DirectMessages do 
				if message.recipient_username == update_info.username 
				   or message.authorname == update_info.username
				then
					table.insert(messages_to_give_user, message)
				end
			end
			table.sort(messages_to_give_user, function(a, b)
				return a.timestamp < b.timestamp
			end)
			return json.encode(messages_to_give_user)
		elseif request.path == "/get-clients" then
			return json.encode(CurrentClients)
		elseif request.path == "/connect" then
			local connection_info: ConnectionInfo = json.decode(request.body)
			local username = connection_info.username
			local user_info = CurrentClients[username]
			if user_info ~= nil then
				if user_info.pin == connection_info.pin then
					return json.encode({ok = true})
				else
					return json.encode({
						ok = false, 
						err = "wrong pin",
					})
				end
			else
				local new_user_info: UserInfo = {
					username = connection_info.username,
					pin = connection_info.pin,
					last_updated = datetime.now().unixTimestamp,
				}
				CurrentClients[connection_info.username] = new_user_info
				return json.encode({
					ok = true, 
					new_account = true,
				})
			end
		else
			print(request)
			return "unsupported path"
		end
	end
})