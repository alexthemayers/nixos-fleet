# How-To: Manage Secrets in NixOS

This guide details how to securely manage secrets in the `nixos-fleet` repository without leaking plain-text credentials
into the world-readable `/nix/store`.

## The Problem: Nix Store Leaks

NixOS configurations are compiled into the `/nix/store`. Any string literal defined in a `.nix` file (e.g.
`password = "my-secret";`) will end up in a configuration file in the Nix store, accessible to *any* user on the system.

To prevent this, we use **SOPS** (`sops-nix`) to decrypt secrets at boot time into a protected RAM-backed filesystem (
`/run/secrets/`). However, we still need to pass these paths to our services without hardcoding the secret values
themselves.

Here are the three standard implementation patterns:

## Pattern 1: Systemd `EnvironmentFile` (via `sops.templates`)

This is the most common and robust approach. We generate a template that references the SOPS placeholder, and configure
the systemd service to load the rendered template as an environment file.

### Implementation

1. **Define the secret in `.sops.yaml` and create it.**
2. **Declare the secret in your Nix config**, ensuring the service user owns it:
   ```nix
   sops.secrets."myservice/api_token" = {
     owner = "myservice";
   };
   ```
3. **Create a `sops.template`** using the placeholder syntax:
   ```nix
   sops.templates."myservice-env" = {
     owner = "myservice";
     content = ''
       API_TOKEN="${config.sops.placeholder."myservice/api_token"}"
     '';
   };
   ```
4. **Inject it into the systemd service** using `EnvironmentFile`:
   ```nix
   systemd.services.myservice.serviceConfig.EnvironmentFile = [ 
     config.sops.templates."myservice-env".path 
   ];
   ```

### Tradeoffs

- **Pros**: Works with almost any application that accepts environment variables. Prevents secret leakage entirely.
- **Cons**: Requires the application to support configuring secrets via environment variables.

---

## Pattern 2: Reference by Path

Some applications natively support reading a secret from a file path rather than requiring the raw string in their
configuration file.

### Implementation (Grafana Example)

Grafana allows using `$__file{/path/to/file}` in its configuration to resolve secrets at runtime.

1. **Declare the secret**:
   ```nix
   sops.secrets."grafana/admin_password" = {
     owner = "grafana";
   };
   ```
2. **Reference the path** in the Nix module:
   ```nix
   services.grafana.settings.security.admin_password = "$__file{${config.sops.secrets."grafana/admin_password".path}}";
   ```

### Tradeoffs

- **Pros**: Very clean Nix code. No need for `sops.templates`.
- **Cons**: Only works if the specific application (e.g., Grafana, Vikunja via `password = { file = ... }`) has built-in
  support for reading configuration values from files.

---

## Pattern 3: Dynamic Template Evaluation (Inline Scripting)

If a service requires a secret in a static configuration file and does *not* support environment variables or file path
references, you may need to use inline evaluation if the application's configuration parser supports it.

### Implementation (GitLab Example)

GitLab's `gitlab.rb` is evaluated as Ruby code when `gitlab-ctl reconfigure` runs. We can embed Ruby code to read the
SOPS file directly:

```nix
services.gitlab.extraConfig = ''
  gitlab_rails['omniauth_providers'] = [
    {
      "name" => "openid_connect",
      "args" => {
        "client_secret" => "<%= File.read('${config.sops.secrets."gitlab/client_secret".path}').strip %>"
      }
    }
  ]
'';
```

### Tradeoffs

- **Pros**: Solves edge cases where apps strictly require the secret in their config file.
- **Cons**: Highly application-dependent (requires the app config to be evaluated as a script, like Ruby in GitLab or
  PHP in some other apps).
