"use strict";
"require view";
"require poll";
"require request";
"require dom";

function asText(value) {
  if (value === null || value === undefined || value === "") {
    return "-";
  }
  return String(value);
}

function yesNo(value) {
  return value ? _("Yes") : _("No");
}

function buildRow(label, value) {
  return E("tr", {}, [
    E("td", { style: "width: 40%; font-weight: 600;" }, [label]),
    E("td", {}, [asText(value)]),
  ]);
}

function renderStatusTable(data) {
  var metrics = data.metrics || {};
  var actions = data.actions || {};
  var service = data.service || {};

  return E("table", { class: "table" }, [
    buildRow(_("Last update"), data.timestamp),
    buildRow(_("Collect enabled"), yesNo(data.enabled)),
    buildRow(_("Endpoint"), data.endpoint),
    buildRow(_("Auth mode"), data.auth_mode),
    buildRow(_("Auth state"), data.auth_state),
    buildRow(_("Ping target"), metrics.ping_target),
    buildRow(_("Latency avg (ms)"), metrics.latency_avg_ms),
    buildRow(_("Packet loss (%)"), metrics.packet_loss_percent),
    buildRow(_("Network reachable"), yesNo(metrics.network_reachable)),
    buildRow(_("Speed (kbps)"), metrics.speed_kbps),
    buildRow(_("Speed test status"), metrics.speedtest_status),
    buildRow(_("ua3f service"), service.ua3f_service),
    buildRow(_("ua3f running"), yesNo(service.ua3f_running)),
    buildRow(_("ua3f restarted in last cycle"), yesNo(service.ua3f_restarted)),
    buildRow(_("Timeout action triggered"), yesNo(actions.timeout_triggered)),
    buildRow(_("Timeout action exit code"), actions.timeout_exit_code),
    buildRow(_("Last post success"), yesNo(actions.last_post_ok)),
    buildRow(_("Last post error"), actions.last_post_error),
  ]);
}

return view.extend({
  handleSave: null,
  handleSaveApply: null,
  handleReset: null,

  render: function () {
    var statusNode = E("div", { class: "cbi-section-node" }, [
      _("Waiting for first report..."),
    ]);

    function refreshStatus() {
      return request
        .get(L.url("admin/services/icenetwork_esp/status"), {
          headers: { Accept: "application/json" },
        })
        .then(function (response) {
          var data = {};

          if (!response.ok) {
            dom.content(
              statusNode,
              E("p", { class: "alert-message warning" }, [
                _("Failed to fetch status"),
                ": HTTP ",
                String(response.status),
              ]),
            );
            return;
          }

          try {
            data = JSON.parse(response.responseText || "{}");
          } catch (e) {
            data = {};
          }

          dom.content(statusNode, renderStatusTable(data));
        })
        .catch(function () {
          dom.content(
            statusNode,
            E("p", { class: "alert-message warning" }, [
              _("Failed to fetch status"),
            ]),
          );
        });
    }

    poll.add(refreshStatus, 5);
    refreshStatus();

    return E("div", { class: "cbi-map" }, [
      E("h2", {}, [_("IceNetwork ESP Status")]),
      E("div", { class: "cbi-section" }, [
        E("h3", {}, [_("Realtime Status")]),
        statusNode,
      ]),
    ]);
  },
});
