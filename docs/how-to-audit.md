# How to audit this fleet

Claims about the running fleet need a tag. Mixing them is how the 2026-08
investigation rated a working Alertmanager config Critical.

Severity:

- **Critical** — can lose data, lose the fleet, or give an attacker a path
  that does not require much luck.
- **High** — the design does not do what it claims, or a failure of one
  component takes down more than it should.
- **Medium** — correctness, drift, footguns, unpaid maintenance.
- **Low** — noise, taste, small inconsistencies.

Every claim is tagged with how it was established:

- **[eval]** — verified by `nix eval` against the evaluated NixOS
  configuration. Highest confidence.
- **[live]** — observed on a running host via SSH.
- **[tree]** — read from source. Correct about what is written; may miss
  module defaults.
- **[inference]** — reasoning about upstream behavior that was not
  directly verified. Treat with suspicion.

Do not treat **[tree]** as **[eval]**. Reading `allowedTCPPorts` does not
prove an exporter is closed: nixpkgs `openFirewall` can emit an nftables
accept with no interface match.

Product and topology freezes live in [adr/](adr/README.md). Closed coding
slips live in [todo-deviations.md](todo-deviations.md).
