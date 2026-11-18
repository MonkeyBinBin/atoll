# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

## After triage

Two more states sit outside the triage roles; they are the same strings Wayfinding uses (see `issue-tracker.md`):

| Label in our tracker | Meaning                                                               |
| -------------------- | --------------------------------------------------------------------- |
| `claimed`            | An agent or human has started work; set it before doing anything else |
| `resolved`           | Done: the checklist is ticked and the outcome is under `## Comments` |

`resolved` is terminal. Reopening means setting the issue back to a triage role and saying why under `## Comments`.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.
