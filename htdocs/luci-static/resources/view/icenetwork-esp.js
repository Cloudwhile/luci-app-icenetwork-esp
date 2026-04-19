"use strict";
"require view";
"require form";
"require uci";

return view.extend({
  load: function () {
    return uci.load("icenetwork_esp");
  },

  render: function () {
    var m, s, o, s5, s2, s3, s4;

    m = new form.Map(
      "icenetwork_esp",
      _("IceNetwork ESP"),
      _(
        "Collect network metrics, guard ua3f service, and report all telemetry to ESP.",
      ),
    );

    s = m.section(form.TypedSection, "core", _("Core Settings"));
    s.anonymous = true;
    s.addremove = false;

    o = s.option(form.Flag, "enabled", _("Enable"));
    o.rmempty = false;

    o = s.option(form.Value, "server", _("Server Address"));
    o.datatype = "host";
    o.placeholder = "192.168.1.2";

    o = s.option(form.Value, "port", _("Server Port"));
    o.datatype = "port";
    o.placeholder = "9000";

    o = s.option(form.Value, "esp_path", _("ESP API Path"));
    o.placeholder = "/metrics";

    s5 = m.section(form.TypedSection, "core", _("ESP Authentication"));
    s5.anonymous = true;
    s5.addremove = false;

    o = s5.option(form.ListValue, "auth_mode", _("Auth Mode"));
    o.value("none", _("None"));
    o.value("token", _("Token Header"));
    o.value("hmac", _("HMAC-SHA256"));
    o.default = "none";

    o = s5.option(form.Value, "auth_header_name", _("Token Header Name"));
    o.placeholder = "X-Auth-Token";
    o.depends("auth_mode", "token");

    o = s5.option(form.Value, "auth_token", _("Token Value"));
    o.password = true;
    o.depends("auth_mode", "token");

    o = s5.option(
      form.Value,
      "hmac_header_name",
      _("HMAC Signature Header Name"),
    );
    o.placeholder = "X-Signature";
    o.depends("auth_mode", "hmac");

    o = s5.option(
      form.Value,
      "hmac_timestamp_header",
      _("HMAC Timestamp Header Name"),
    );
    o.placeholder = "X-Timestamp";
    o.depends("auth_mode", "hmac");

    o = s5.option(form.Value, "hmac_secret", _("HMAC Secret"));
    o.password = true;
    o.depends("auth_mode", "hmac");

    o = s.option(form.Value, "check_interval", _("Collect Interval (seconds)"));
    o.datatype = "uinteger";
    o.placeholder = "60";

    s2 = m.section(form.TypedSection, "core", _("Ping Detection"));
    s2.anonymous = true;
    s2.addremove = false;

    o = s2.option(form.Value, "ping_target", _("Ping Target"));
    o.datatype = "host";
    o.placeholder = "8.8.8.8";

    o = s2.option(form.Value, "ping_count", _("Ping Count"));
    o.datatype = "uinteger";
    o.placeholder = "4";

    o = s2.option(
      form.Value,
      "ping_timeout",
      _("Ping Timeout Per Probe (seconds)"),
    );
    o.datatype = "uinteger";
    o.placeholder = "2";

    o = s2.option(
      form.Value,
      "timeout_loss_threshold",
      _("Timeout Trigger Packet Loss (%)"),
    );
    o.datatype = "range(1,100)";
    o.placeholder = "100";

    o = s2.option(form.Value, "timeout_command", _("Command on Ping Timeout"));
    o.placeholder = "/etc/init.d/network restart";

    s3 = m.section(form.TypedSection, "core", _("Speed Test"));
    s3.anonymous = true;
    s3.addremove = false;

    o = s3.option(form.Flag, "speedtest_enabled", _("Enable Speed Test"));
    o.rmempty = false;

    o = s3.option(form.Value, "speedtest_url", _("Speed Test URL"));
    o.placeholder = "http://speed.cloudflare.com/__down?bytes=5000000";

    o = s3.option(
      form.Value,
      "speedtest_timeout",
      _("Speed Test Timeout (seconds)"),
    );
    o.datatype = "uinteger";
    o.placeholder = "15";

    o = s3.option(
      form.Value,
      "speedtest_interval",
      _("Speed Test Interval (seconds)"),
    );
    o.datatype = "uinteger";
    o.placeholder = "300";

    s4 = m.section(form.TypedSection, "core", _("UA3F Watchdog"));
    s4.anonymous = true;
    s4.addremove = false;

    o = s4.option(
      form.Flag,
      "ua3f_autostart",
      _("Auto Start ua3f When Stopped"),
    );
    o.rmempty = false;

    o = s4.option(form.Value, "ua3f_service", _("ua3f Service Name"));
    o.placeholder = "ua3f";

    return m.render();
  },
});
