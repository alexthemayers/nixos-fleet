---
status: "{proposed | rejected | accepted | deprecated | superseded by [YYYY-MM-DD-slug.md](YYYY-MM-DD-slug.md)}"
date: "{YYYY-MM-DD when the decision was last updated}"
# Optional. Remove unused keys.
# deciders: "{who decided}"
# consulted: "{two-way consult}"
# informed: "{one-way inform}"
---

# {short title of solved problem and solution}

Copy this file to `YYYY-MM-DD-slug.md`. One decision per file. Index it in
[README.md](README.md). Format: [MADR 3.0.0](https://adr.github.io/madr/).

## Context and Problem Statement

{Context and the question being decided, in two or three sentences.}

## Decision Drivers

* {force or concern}
* {force or concern}

## Considered Options

* {option 1}
* {option 2}
* {option 3}

## Decision Outcome

Chosen option: "{option 1}", because {justification}.

### Consequences

* Good, because {positive consequence}
* Bad, because {negative consequence}

## Validation

{How compliance is confirmed: module path, alert, dashboard, make target,
or a review after switch.}

## Pros and Cons of the Options

### {option 1}

* Good, because {argument}
* Bad, because {argument}

### {option 2}

* Good, because {argument}
* Bad, because {argument}

## More Information

{Links to the service doc, related ADRs, or when to revisit.}
