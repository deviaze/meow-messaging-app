--!nonstrict
print("starting client")

local http = require("@std/net/http")
local json = require("@std/json")
local colors = require("@std/colors")
local time = require("@std/time")
local datetime = require("@std/time/datetime")
local input = require("@std/io/input")
local output = require("@std/io/output")
local crypt = require("@std/crypt")
local process = require("@std/process")
local aes = crypt.aes

local SERVER_IP_AND_PORT = if _G.PROD then "http://67.205.186.23:8080" else "http://localhost:4242"

--- general state info we keep about ourselves
type Client = {
	username: string,
	pin: string,
	symmetric_key: string,
	server_public_key: string?,
}

--- format of messages we send from client to server
type ClientMessage = {
	from_username: string,
	from_pin: string,
	from_symmetric_key: string,
	to_username: string,
	contents: string,
	reply_to_messageid: number?,
}

--- format of messages we receive from the server
type Message = {
	id: number,
	from_username: string,
	to_username: string,
	contents: string,
	reply_to_messageid: number?,
	timestamp: number,
}

--

local client: Client = {
	username = "",
	pin = "",
	symmetric_key = aes.generatekey(),
}

-- helper functions
local function encrypt_for_server(t: { [any]: any }): string
	if client.server_public_key then
		local plaintext = json.encode(t)
		return crypt.rsa.encrypt(plaintext, client.server_public_key)
	else
		error("server public key not found")
	end
end

-- main client functionality

-- get public key off server so we can communicate to the server with encryption
type GetKeyResponse = { public_key: string }
local key_response: GetKeyResponse = http.get {
	url = `{SERVER_IP_AND_PORT}/key/get`
}:unwrap_json()

client.server_public_key = key_response.public_key

local function aes_decrypt_response(response: any)
	if response.ok and response.body then
		local body = response.body
		return json.decode(
			aes.decrypt(body, client.symmetric_key)
		)
	end
	error("unable to decrypt response")
end

-- log in or create user on the server
local function login(tries: number)
	if tries > 0 then
		print(`\n{colors.red("Invalid username or pin, please try again.")}`)
	end
	local requested_username = input.get("  Username: ")
	local alleged_pin = input.get("  Pin: ")
	local login_or_create_account_response = http.post {
		url = `{SERVER_IP_AND_PORT}/login-create-account`,
		body = encrypt_for_server {
			username = requested_username,
			pin = alleged_pin,
			symmetric_key = client.symmetric_key,
		}
	}
	if login_or_create_account_response.body then
		local response = json.decode(aes.decrypt(login_or_create_account_response.body, client.symmetric_key)) :: {
			ok: true,
			message: "Logged in" | "User created!"
		} | {
			ok: false,
			err: "Incorrect username or password"
		}
		if response.ok then
			print(`\n{colors.green(response.message)}`)
			client.username = requested_username
			client.pin = alleged_pin
		else
			login(tries + 1)
		end
	end
end

print("Login")
login(0)

-- main gameplay loop

local american_local_time = `{datetime.common_formats.SHORT_DATE} @ {datetime.common_formats["HH:MM (AM/PM)"]}`
while true do
	output.clear()
	-- fetch list of all clients from server
	local connected_clients = aes_decrypt_response(
		http.get {
			url = `{SERVER_IP_AND_PORT}/get-clients`,
			body = encrypt_for_server {
				symmetric_key = client.symmetric_key,
				username = client.username,
				pin = client.pin,
			}
		}
	) :: { 
		{ username: string, last_seen: number }
	}

	-- keep a small track of clients in a dictionary
	local active_clients: { [string]: { username: string, last_seen: number } } = {}

	print(colors.bold.yellow("Clients"))
	print(colors.cyan(`  {colors.bold.cyan("Username")}     {colors.bold.white("Last seen")}`))
	print(colors.bold.white("  -----------------------------------"))
	for _, connected_client in connected_clients do
		active_clients[connected_client.username] = connected_client
		local formatted_dt = datetime.from(connected_client.last_seen):format_local(american_local_time)
		print(`  {colors.bold.cyan(connected_client.username)}       {formatted_dt}`)
	end
	print(colors.bold.white("  -----------------------------------"))

	local messages = aes_decrypt_response(
		http.get {
			url = `{SERVER_IP_AND_PORT}/update`,
			body = encrypt_for_server {
				username = client.username,
				pin = client.pin,
				symmetric_key = client.symmetric_key
			}
		}
	) :: { Message }
	
	print(colors.bold.yellow("Messages"))
	for _, message in messages do
		local formatted_dt = datetime.from(message.timestamp):format_local(american_local_time)
		if client.username == message.from_username and client.username == message.to_username then
			print(`  {colors.bold.blue("self")}: {message.contents} ({formatted_dt})`)
		elseif client.username == message.from_username then
			print(`  {colors.bold.blue(message.from_username)} to {colors.bold.green(message.to_username)}: {message.contents} ({colors.cyan(formatted_dt)})`)
		else
			print(`  {colors.bold.green(message.from_username)} to {colors.bold.blue(message.to_username)}: {message.contents} ({colors.cyan(formatted_dt)})`)
		end
	end

	print("\n")

	local action = input.get(`{colors.bold.blue("R")} to refresh, {colors.bold.green("S")} to send a message, and {colors.bold.red(".exit")} to exit: `)
	if action == ".exit" then
		process.exit(0)
	elseif action == "R" then
		continue
	elseif action == "S" then
		local function send_message()
			local recipient_username = input.get(`Send a message to ({colors.bold.white("username")}): `)
			if active_clients[recipient_username] then
				local message_contents = input.get(`{colors.bold.green("Message: ")}`)
				if #message_contents > 0 then
					local new_message: ClientMessage = {
						from_username = client.username,
						from_pin = client.pin,
						from_symmetric_key = client.symmetric_key,
						to_username = recipient_username,
						contents = message_contents,
					}
					local send_confirmation = http.post {
						url = `{SERVER_IP_AND_PORT}/send-message`,
						body = encrypt_for_server(new_message)
					}
					if send_confirmation.ok then
						print(colors.bold.green("\nMessage sent"))
						time.wait(0.425)
					end
				end
			else
				print("That user doesn't exist. Try again?")
				send_message()
			end
		end
		send_message()
	end
end


return client
