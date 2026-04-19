module("luci.controller.icenetwork_esp", package.seeall)

function index()
    entry({"admin", "services", "icenetwork_esp", "status"}, call("action_status")).leaf = true
end

function action_status()
    local fs = require "nixio.fs"
    local jsonc = require "luci.jsonc"
    local http = require "luci.http"

    local status_raw = fs.readfile("/var/run/icenetwork_esp/status.json")
    local status_obj = {}

    if status_raw and #status_raw > 0 then
        status_obj = jsonc.parse(status_raw) or {}
    end

    http.prepare_content("application/json")
    http.write_json(status_obj)
end
