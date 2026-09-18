{
  host = "proxmox-applications-2";
  port = 8080;
  docs = "docs/services/gitlab.md";
  module = "services/gitlab.nix";
  dashboard = "fleet-gitlab.json";
  edge = {
    domain = "gitlab.alexmayers.co.za";
    rateLimit = "heavy";
    wafExtraDirectives = ''
      SecRule REQUEST_URI "@contains .git/" "id:10301,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=930130,ctl:ruleRemoveById=920420"
      SecRule REQUEST_URI "@beginsWith /api/graphql" "id:10302,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=942290,ctl:ruleRemoveById=932160,ctl:ruleRemoveById=932235"
      SecRule REQUEST_URI "@streq /api/server/version" "id:10303,phase:1,pass,t:none,nolog,ctl:ruleRemoveById=920420"
    '';
  };
  probe = {
    public = true;
    path = "/users/sign_in";
  };
}
