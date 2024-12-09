--!strict

local http_server = require("@std/net/http/server")
local json = require("@std/json")
local crypt = require("@std/crypt")
local datetime = require("@std/time/datetime")

type ClientInfo = {
	symmetric_key: string,
	username: string,
	pin: string,
	last_seen: number,
}

type Message = {
	id: number,
	from_username: string,
	to_username: string,
	contents: string,
	reply_to_messageid: number?,
	timestamp: number,
}

type Clients = {
	[--[[username: ]] string]: ClientInfo
}

local clients: Clients = {}
local server_keys = crypt.rsa.generatekeys()

local messages: { Message } = {}

local PORT = if _G.PROD then 8080 else 4242
local SERVER_ADDRESS = if _G.PROD then "http://67.205.186.23" else "localhost"
local SERVER_ADDRESS_AND_PORT = if _G.PROD then `{SERVER_ADDRESS}:{PORT}` else `localhost:{PORT}`

print(`runnign server on {SERVER_ADDRESS_AND_PORT}`)

--- wrapper to return a ServeResponse table
local function method_not_allowed(expected: string, got: string): http_server.ServeResponse
	return {
		status_code = "405 Method Not Allowed",
		content_type = "Text",
		body = `405 Method Not Allowed; expected {expected}, got: {got}`
	}
end

local function unauthorized(symmetric_key: string): http_server.ServeResponse
	local unauthorized_message = json.encode { ok = false, err = "Unauthorized" }
	return {
		status_code = "401 Unauthorized",
		content_type = "Text",
		body = crypt.aes.encrypt(unauthorized_message, symmetric_key)
	}
end

--- wrapper to encrypt a table with the AES key provided by the client
local function encrypt_for_client(client: ClientInfo, t: { [any]: any }): http_server.ServeResponse
	local aes_encrypted_message = crypt.aes.encrypt(json.encode(t), client.symmetric_key)
	return {
		status_code = "200 OK",
		content_type = "Text",
		body = aes_encrypted_message
	}
end

--- wrapper to decrypt the body of a request with the server's private key
local function decrypt_body(ciphertext: string): { [any]: any }
	local plaintext = crypt.rsa.decrypt(ciphertext, server_keys.private)
	return json.decode(plaintext)
end

http_server.serve {
	address = SERVER_ADDRESS,
	port = PORT,
	handler = function(request: http_server.ServeRequest)
		if request.path == "/key/get" then
			if request.method == "GET" then
				return {
					status_code = "200 OK",
					content_type = "JSON",
					body = json.encode {
						public_key = server_keys.public
					}
				}
			else
				return method_not_allowed("GET", request.method)
			end
		elseif request.path == "/login-create-account" then
			if request.method == "POST" then
				local request_username_info = decrypt_body(request.body) :: {
					symmetric_key: string,
					username: string,
					pin: string,
				}
				local existing_client = clients[request_username_info.username]
				if existing_client then
					if existing_client.pin == request_username_info.pin then
						-- valid user, we need to update the symmetric key and log in time
						existing_client.symmetric_key = request_username_info.symmetric_key
						existing_client.last_seen = datetime.now().unix_timestamp
						return encrypt_for_client(existing_client, {
							ok = true,
							message = "Logged in"
						})
					else
						return {
							status_code = "401 Unauthorized",
							content_type = "Text",
							body = crypt.aes.encrypt(
								json.encode { ok = false, err = "Incorrect username or pin" }, 
								request_username_info.symmetric_key
							)
						}
					end
				else -- create a new user
					local new_client: ClientInfo = {
						username = request_username_info.username,
						symmetric_key = request_username_info.symmetric_key,
						pin = request_username_info.pin,
						last_seen = datetime.now().unix_timestamp,
					}
					clients[new_client.username] = new_client
					return {
						status_code = "201 Created",
						content_type = "Text",
						body = crypt.aes.encrypt(
							json.encode { ok = true, message = "User created!" },
							request_username_info.symmetric_key
						)
					}
				end
			else
				return method_not_allowed("POST", request.method)
			end
		elseif request.path == "/get-clients" then
			if request.method == "GET" then
				local body = decrypt_body(request.body) :: {
					username: string,
					pin: string,
					symmetric_key: string,
				}
				local existing_client = clients[body.username]
				if  existing_client 
				    and existing_client.pin == body.pin 
					and existing_client.symmetric_key == body.symmetric_key 
				then
					type ClientInfoRedacted = { username: string, last_seen: number }
					local all_clients: { ClientInfoRedacted } = {}
					for _, client in clients do
						table.insert(all_clients, {
							username = client.username,
							last_seen = client.last_seen,
						})
					end
					return encrypt_for_client(existing_client, all_clients)
				else
					return unauthorized(body.symmetric_key)
				end
			end
		elseif request.path == "/update" then
			if request.method == "GET" then
				local body = decrypt_body(request.body) :: {
					username: string,
					pin: string,
					symmetric_key: string,
				}
				local existing_client = clients[body.username]
				if  existing_client
				    and existing_client.pin == body.pin
				    and existing_client.symmetric_key == body.symmetric_key
				then
					existing_client.last_seen = datetime.now().unix_timestamp
					local relevant_messages: { Message } = {}
					for _, message in messages do
						if  existing_client.username == message.from_username
						    or existing_client.username == message.to_username
						then
							table.insert(relevant_messages, message)
						end
					end
					return encrypt_for_client(existing_client, relevant_messages)
				else
					return unauthorized(body.symmetric_key)
				end
			else
				return method_not_allowed("POST", request.method)
			end
		elseif request.path == "/send-message" then
			if request.method == "POST" then
				local body = decrypt_body(request.body) :: {
					from_username: string,
					from_pin: string,
					from_symmetric_key: string,
					to_username: string,
					contents: string,
					reply_to_messageid: number?,
				}
				local from_client = clients[body.from_username]
				if  from_client
				    and from_client.pin == body.from_pin
				    and from_client.symmetric_key == body.from_symmetric_key
				then
					local timestamp = datetime.now().unix_timestamp
					local message_id = #messages + 1
					table.insert(messages, {
						id = message_id,
						from_username = from_client.username,
						to_username = body.to_username,
						contents = body.contents,
						timestamp = timestamp,
						reply_to_messageid = body.reply_to_messageid or nil
					})
					-- update last seen
					from_client.last_seen = timestamp
					local message_sent_confirmation = json.encode { ok = true, message = "message sent"}
					return {
						status_code = "201 Created",
						content_type = "Text",
						body = crypt.aes.encrypt(message_sent_confirmation, from_client.symmetric_key)
					}
				end
			end
		end

		return {
			status_code = "404 Not Found",
			content_type = "Text",
			body = "404 Not Found"
		}
	end
}

return nil