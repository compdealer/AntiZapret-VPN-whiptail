# whiptail UI for `setup.sh`

Interactive TUI for the 39 questions of `setup.sh` in this fork (whiptail, Debian `newt` 0.52.x).
The questions, their order, default answers and wording are copied from upstream `GubernievS/AntiZapret-VPN`
unchanged; only the input layer is replaced. Logic after the questions (installation) is untouched.

## Files

| file | contents |
|---|---|
| `spec.md` | full specification: bootstrap, mode selection (`AZ_UI`, `NO_WHIPTAIL`, `QUESTIONS_ONLY`), helpers, dialogs, acceptance checks |
| `spec-dialogs.md` | generated table of the 39 dialogs (from the upstream `read -rp` calls) |
| `prompts-inventory.md` | generated inventory of the question sites |
| `tooling-choice.md` | why whiptail and not dialog/gum/fzf, measured package sizes |
| `plan.md` | work journal: decisions, test ladder T0-T3, measurements on real terminals, known limitations |

## Behaviour notes

- `AZ_UI=whiptail|plain` forces the interface; without it the script asks a plain-text question first,
  because whiptail cannot be used before checking it exists.
- `NO_WHIPTAIL=1` or a non-terminal stdin always falls back to the original plain prompts.
- Colour scheme: the newt palette `NEWT_COLORS` is set to the Orange theme
  (`cp737.net/blog/whiptail-orange-theme`) only when the user has not set the variable; plain mode
  and `QUESTIONS_ONLY` are unaffected.
- `QUESTIONS_ONLY=1` prints the resulting `setup` file (68 lines, upstream format) and exits before
  any system change: same answers in, same file out.
- `SSH_PROTECTION=n` is answered by the operator; the UI does not read the previous `setup` file
  (upstream behaviour is kept: answers rewrite it).
