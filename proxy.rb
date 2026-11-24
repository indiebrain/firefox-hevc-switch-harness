#!/usr/bin/env ruby
# frozen_string_literal: true

# Serves the test page and relays video requests to an HLS stream on another
# host, so the page and the stream share an origin. For a stream that allows
# only its own site (Bunny Stream's hotlink protection answers 403 without a
# matching Referer), the relay adds the Referer a browser page cannot set.
#
#   VIDEO_BASE=https://example.b-cdn.net/<video-id> ruby proxy.rb
#   # then open http://localhost:8765/
#
# Environment:
#   VIDEO_BASE  required: URL prefix of the folder that holds playlist.m3u8
#   REFERER     optional: Referer sent upstream, for a stream you own
#   PORT        local port (default: 8765)
#
# GET /video/playlist.m3u8?only=avc1 keeps only the variants whose CODECS
# start with "avc1", to compare against a single-format playlist.

require "socket"
require "net/http"
require "uri"

abort "Set VIDEO_BASE to the URL prefix of the folder that holds playlist.m3u8" if ENV["VIDEO_BASE"].to_s.empty?

VIDEO_BASE = ENV["VIDEO_BASE"].chomp("/")
REFERER = ENV["REFERER"]
PORT = Integer(ENV.fetch("PORT", "8765"))
PAGE = File.join(__dir__, "index.html")
SAFE_PATH = %r{\A[A-Za-z0-9_./-]+\z}

def respond(client, status, headers, body)
  client.write("HTTP/1.1 #{status}\r\n")
  headers.merge("Content-Length" => body.bytesize.to_s, "Connection" => "close")
         .each { |name, value| client.write("#{name}: #{value}\r\n") }
  client.write("\r\n")
  client.write(body)
end

# Keeps an #EXT-X-STREAM-INF line and the URI line after it only when its
# CODECS attribute starts with the given prefix.
def filter_variants(playlist, codec_prefix)
  lines = playlist.lines
  kept = []
  index = 0
  while index < lines.length
    line = lines[index]
    if line.start_with?("#EXT-X-STREAM-INF")
      kept.push(line, lines[index + 1]) if line[/CODECS="([^"]*)"/, 1].to_s.start_with?(codec_prefix)
      index += 2
    else
      kept.push(line)
      index += 1
    end
  end
  kept.join
end

def relay(client, path, query, range)
  return respond(client, "400 Bad Request", {}, "bad path\n") unless path.match?(SAFE_PATH) && !path.include?("..")

  upstream = URI("#{VIDEO_BASE}/#{path}")
  request = Net::HTTP::Get.new(upstream)
  request["Referer"] = REFERER if REFERER
  request["Range"] = range if range
  response = Net::HTTP.start(upstream.host, upstream.port, use_ssl: true) { |http| http.request(request) }

  body = response.body.to_s
  only = query[/(?:\A|&)only=([A-Za-z0-9]+)/, 1]
  body = filter_variants(body, only) if only && path.end_with?(".m3u8")

  headers = { "Content-Type" => response["Content-Type"] || "application/octet-stream", "Cache-Control" => "no-store" }
  headers["Content-Range"] = response["Content-Range"] if response["Content-Range"]
  respond(client, "#{response.code} #{response.message}", headers, body)
end

def handle(client)
  request_line = client.gets.to_s
  headers = {}
  while (line = client.gets) && line != "\r\n"
    name, value = line.split(":", 2)
    headers[name.downcase] = value.strip
  end

  method, target = request_line.split(" ")
  path, query = target.to_s.split("?", 2)
  query = query.to_s

  if method != "GET"
    respond(client, "405 Method Not Allowed", {}, "GET only\n")
  elsif path == "/"
    respond(client, "200 OK", { "Content-Type" => "text/html; charset=utf-8", "Cache-Control" => "no-store" }, File.binread(PAGE))
  elsif path.start_with?("/video/")
    relay(client, path.delete_prefix("/video/"), query, headers["range"])
  else
    respond(client, "404 Not Found", {}, "not found\n")
  end
rescue StandardError => error
  warn "#{request_line.strip}: #{error.class}: #{error.message}"
  respond(client, "502 Bad Gateway", {}, "#{error.message}\n") rescue nil
ensure
  client.close
end

server = TCPServer.new("127.0.0.1", PORT)
puts "Relaying #{VIDEO_BASE}#{" with Referer #{REFERER}" if REFERER}"
puts "Open http://localhost:#{PORT}/"
loop { Thread.new(server.accept) { |client| handle(client) } }
