# Messaging Client for COMP 3825

A simple http-based direct messaging program written in Luau.

By Dev Chrysalis Dalal & Suchir Reganti

This repository contains both the client and server components of this project. I'm currently hosting the server code on my virtual private server (VPS) at a static IP address, so you should just be able to run the client-side code contained in `./src/client/main.luau` and this messaging client should *just work (tm)*.

## Overview

The Meow (we couldn't decide on a better name) Messaging App is a very simple HTTP-based terminal messaging program that allows you tosend texts to other users anywhere in the world. It works by bouncing messages off a VPS that caches `POST /send-message` requests and returns them to `GET /update` requests from other users.

As evidenced by earlier assignments for this class, sending messages from one computer to another through direct client-to-client communication (via personal IP addresses and ports) is a difficult proposition given modern network security and port blocking.

On the other hand, structured HTTP APIs are a tried-and-true method to transfer structured data reliably over the internet, and shouldwork anywhere on this planet as long as your server has a static IP and good uptime.

As I already have a DigitalOcean VPS cloud server with a static IP address for hosting my Lune/Luau-based Discord bot, websites, and other projects, we decided it should be relatively trivial to run a `net.serve` webserver on it for this assignment and expose a simple HTTP API surface.

### Technologies/Dependencies

We chose to write this project in the Luau programming language to take advantage of its familiarity, simple syntax and usage, and its gradual type system.
Luau types allow us to easily define our JSON interchange formats into the code itself and statically verify that the data we pass into our HTTP APIs matches the data we expect to receive.
This makes it extremely easy to write, document, and use API surfaces within our codebase.

To run Luau code outside an embedded environment, you can use a Luau runtime such as Lune or Zune. In our current implementation, we use Lune to run client code and Zune for server code.

The Lune runtime is the most popular standalone runtime for the Luau language (analogous to `node` for JavaScript), and provides easy access to core general-purpose-programming functionality like net requests, websockets, http servers, command-line input and output, shell commands, data serialization, etc.

Zune is an alternate Luau runtime that implements many Lune-inspired APIs but is built in Zig instead of Rust.

Although we planned to use Lune on both the client and server, we hit an implementation bug in Lune's `net.serve` that caused our webserver to irrevocably yield after a few requests. As Zune also implements `net.serve`, we were able to rewrite the code for Zune, which seems to have solved that problem.

## Installation

To run this program, you need the Lune runtime for Luau, which you can download from GitHub releases through GUI or CLI:

https://github.com/lune-org/lune/releases/tag/v0.8.9

We recommend installing this in WSL on Windows, but as Lune is cross-platform, our program should work anywhere Lune is supported.

To install via command-line on Linux (including WSL), use `wget` and `unzip`:

```sh
# on ubuntu (wsl or otherwise)
sudo apt update && sudo apt upgrade
sudo apt install unzip

# change download link if you're on mac or windows outside WSL
wget https://github.com/lune-org/lune/releases/download/v0.8.9/lune-0.8.9-linux-x86_64.zip

unzip ./lune-0.8.9-linux-x86_64.zip

chmod +x ./lune

# launch the client
./lune run .

```

### Editor support

To review this code with proper syntax highlighting and editor support, install the VSCode extension "Luau Language Server" from JohnnyMorganz

## Usage

- `cd` into this folder/workspace
- run the client with `./lune run .`
- enter your username when prompted and press Enter
- to send a message, type in another username, press Enter, type in your message content and press Enter.
- to update messages without sending a message, press Enter twice
- repeat to send/receive messages
- Hit `Ctrl + C` to exit the program
