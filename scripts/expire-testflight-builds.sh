#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.rosehillsolutions.photoswallpaper}"
KEEP_BUILDS="${KEEP_BUILDS:-10}"
APPLY="false"

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--apply] [--keep N]

Expires old TestFlight builds for $APP_BUNDLE_ID through the App Store Connect API.
Runs as a dry run unless --apply is provided.

Required environment:
  ASC_KEY_ID             App Store Connect API key id
  ASC_ISSUER_ID          App Store Connect issuer id
  ASC_PRIVATE_KEY        Contents of the .p8 private key
    or
  ASC_PRIVATE_KEY_PATH   Path to the .p8 private key

Create these in App Store Connect:
  Users and Access -> Integrations -> App Store Connect API -> Generate API Key

Optional environment:
  APP_BUNDLE_ID          Defaults to $APP_BUNDLE_ID
  KEEP_BUILDS            Defaults to $KEEP_BUILDS
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            APPLY="true"
            shift
            ;;
        --keep)
            KEEP_BUILDS="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! [[ "$KEEP_BUILDS" =~ ^[0-9]+$ ]]; then
    echo "--keep must be a non-negative integer." >&2
    exit 2
fi

ruby - "$APP_BUNDLE_ID" "$KEEP_BUILDS" "$APPLY" <<'RUBY'
require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

bundle_id, keep_builds_arg, apply_arg = ARGV
keep_builds = Integer(keep_builds_arg)
apply = apply_arg == "true"

key_id = ENV.fetch("ASC_KEY_ID")
issuer_id = ENV.fetch("ASC_ISSUER_ID")
private_key = ENV["ASC_PRIVATE_KEY"]
private_key_path = ENV["ASC_PRIVATE_KEY_PATH"]

if private_key.to_s.empty? && private_key_path.to_s.empty?
  abort "Set ASC_PRIVATE_KEY to the .p8 contents or ASC_PRIVATE_KEY_PATH to the .p8 file path."
end

def base64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def jwt(key_id, issuer_id, private_key)
  now = Time.now.to_i
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = {
    iss: issuer_id,
    iat: now,
    exp: now + 20 * 60,
    aud: "appstoreconnect-v1"
  }
  signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(payload))}"
  key = OpenSSL::PKey.read(private_key)
  der_signature = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
  sequence = OpenSSL::ASN1.decode(der_signature)
  raw_signature = sequence.value.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
  "#{signing_input}.#{base64url(raw_signature)}"
end

class AppStoreConnect
  API_ROOT = "https://api.appstoreconnect.apple.com"

  def initialize(token)
    @token = token
  end

  def get(path, params = {})
    uri = URI("#{API_ROOT}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    request(uri, Net::HTTP::Get)
  end

  def patch(path, body)
    uri = URI("#{API_ROOT}#{path}")
    request(uri, Net::HTTP::Patch, body)
  end

  private

  def request(uri, request_class, body = nil)
    request = request_class.new(uri)
    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body) if body

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      warn response.body
      raise "App Store Connect request failed: #{response.code} #{response.message}"
    end

    response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
  end
end

private_key = File.read(private_key_path) if private_key.to_s.empty?

client = AppStoreConnect.new(jwt(key_id, issuer_id, private_key))
apps = client.get("/v1/apps", "filter[bundleId]" => bundle_id, "limit" => 1).fetch("data")
abort "No App Store Connect app found for bundle id #{bundle_id}." if apps.empty?

app_id = apps.first.fetch("id")
builds = []
next_url = nil

loop do
  page = if next_url
    uri = URI(next_url)
    client.get(uri.path, URI.decode_www_form(uri.query || "").to_h)
  else
    client.get(
      "/v1/builds",
      "filter[app]" => app_id,
      "fields[builds]" => "version,uploadedDate,expired,processingState",
      "limit" => 200,
      "sort" => "-uploadedDate"
    )
  end

  builds.concat(page.fetch("data"))
  next_url = page.dig("links", "next")
  break unless next_url
end

active_builds = builds.reject { |build| build.fetch("attributes").fetch("expired") }
to_keep = active_builds.first(keep_builds)
to_expire = active_builds.drop(keep_builds)

puts "Bundle id: #{bundle_id}"
puts "Active TestFlight builds: #{active_builds.length}"
puts "Keeping newest builds: #{to_keep.length}"
puts "#{apply ? "Expiring" : "Would expire"} old builds: #{to_expire.length}"
puts

if to_expire.empty?
  puts "Nothing to do."
  exit 0
end

to_expire.each do |build|
  attributes = build.fetch("attributes")
  line = "build #{attributes.fetch("version")} uploaded #{attributes.fetch("uploadedDate")} (#{build.fetch("id")})"

  if apply
    client.patch(
      "/v1/builds/#{build.fetch("id")}",
      {
        data: {
          type: "builds",
          id: build.fetch("id"),
          attributes: {
            expired: true
          }
        }
      }
    )
    puts "Expired #{line}"
  else
    puts "Would expire #{line}"
  end
end

puts
puts "Dry run only. Re-run with --apply to expire these builds." unless apply
RUBY
