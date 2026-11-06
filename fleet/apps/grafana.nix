{
  host = "proxmox-observability-debian";
  port = 3000;
  docs = "docs/services/grafana.md";
  module = null;
  dashboard = "fleet-grafana.json";
  edge = {
    domain = "grafana.alexmayers.co.za";
    rateLimit = "heavy";
    auth = "hybrid";
    apiBearerBypass = true;
    flushInterval = "-1";
    healthUri = "/api/health";
    healthInterval = "5s";
    healthTimeout = "2s";
    healthStatus = "200";
    wafExtraDirectives = ''
      SecRule REQUEST_URI "@beginsWith /api/ds/query" "id:10001,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=932235,ctl:ruleRemoveById=942100,ctl:ruleRemoveById=942550"
      SecRule REQUEST_URI "@beginsWith /api/datasources" "id:10002,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=932235"
      SecRule REQUEST_URI "@beginsWith /explore" "id:10003,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=932230,ctl:ruleRemoveById=932250"
    '';
  };
  probe = {
    public = true;
    path = "/login";
  };
}
