// handoff for the Herdr app: copy the focused terminal's Claude Code
// conversation, paste it as a fork into another pane, or fork it into a split
// on the right.
//
// A key opens this as a popup (keys.json: "mod.open:handoff"); it shows what
// is on the fork clipboard and waits for one key: c copy, v paste, right or f
// fork, Escape. Shipped layouts can't dock a new mod, so a popup is how a mod
// gets keys there. Docked by a layout instead, it also takes handoff.copy,
// handoff.paste and handoff.fork through nextCommand().
//
// Everything about Claude lives in the agentfork CLI (bin/agentfork in the
// handoff repo, linked to ~/.local/bin by `make install`). This runs it with
// the focused terminal's pids, which herdr-core reports, so copy takes exactly
// that terminal's conversation.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { closeOverlay, exec, focused, hc, home, notify, nextCommand, props, readTextFile, run, theme } from "herdr";

const HOME = home();
const BIN = `${HOME}/.local/bin/agentfork`;
const CLIPBOARD = `${HOME}/.local/state/agentfork/clipboard.json`;

const ACTIONS = [
  ["c", "copy", "Copy this terminal's conversation"],
  ["v", "paste", "Paste the copied conversation here, as a fork"],
  ["→", "fork", "Fork this conversation into a split on the right"],
];

function short(p) {
  if (!p) return "";
  return p === HOME ? "~" : p.startsWith(HOME + "/") ? "~" + p.slice(HOME.length) : p;
}

// Quote for a POSIX shell.
function q(s) {
  return "'" + s.replace(/'/g, "'\\''") + "'";
}

export default class Handoff extends View {
  init(_props, cx) {
    this.clip = null;
    this.busy = false;
    // Only the popup takes the keyboard; a docked copy just listens.
    this.popup = Boolean(props()?.overlay);
    if (this.popup) {
      this.handle = cx.focus_handle();
      this.handle.focus();
    }
    cx.spawn(async (cx) => {
      await this.load();
      cx.notify();
    });
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        await this.command(c);
        cx.notify();
      }
    });
  }

  async load() {
    try {
      const text = await readTextFile(CLIPBOARD);
      this.clip = text ? JSON.parse(text) : null;
    } catch {
      this.clip = null;
    }
  }

  dismiss() {
    if (this.popup) closeOverlay(props().overlay);
  }

  // The focused terminal, its pane, folder and the pids running in it.
  async target() {
    const f = focused();
    if (!f?.terminal) return null;
    const pids = [];
    const r = await hc(["get", f.terminal, "--json"]).catch(() => null);
    if (r?.code === 0) {
      try {
        const t = JSON.parse(r.stdout);
        for (const p of [t.foreground?.pid, t.pid]) if (p) pids.push(String(p));
      } catch {}
    }
    return { terminal: f.terminal, pane: f.pane, cwd: f.cwd, pids };
  }

  agentfork(args) {
    return exec(BIN, args).catch((e) => ({ code: 127, stdout: "", stderr: String(e) }));
  }

  // Copy the target's conversation: "copied", "pick" (several could be meant,
  // so a picker is needed) or "failed" (already reported).
  async copy(t) {
    const args = ["copy", "--quiet"];
    for (const p of t.pids) args.push("--pid", p);
    if (t.cwd) args.push("--cwd", t.cwd);
    const r = await this.agentfork(args);
    if (r.code === 0) {
      await this.load();
      notify({ title: "Copied", body: this.describe(), level: "success" });
      return "copied";
    }
    if (r.code === 3) return "pick";
    const why = r.stderr.replace(/^agentfork: /, "").trim() || `agentfork exited with ${r.code}`;
    notify({ title: "handoff", body: why, level: "error" });
    return "failed";
  }

  // A new shell beside the target, running argv.
  split(t, direction, argv) {
    const args = { direction, argv };
    if (t.pane) args.pane = t.pane;
    run("pane.split", args);
  }

  async command(c) {
    if (this.busy) return;
    this.busy = true;
    try {
      const t = await this.target();
      if (!t) {
        notify({ title: "handoff", body: "Focus a terminal first.", level: "warning" });
        return;
      }
      if (c === "copy") {
        // exec, so the picker's pane closes once a conversation is chosen.
        if ((await this.copy(t)) === "pick") this.split(t, "down", ["sh", "-c", `exec ${q(BIN)} copy --pick --notify`]);
      } else if (c === "paste") {
        if (!this.clip?.session_id) {
          notify({ title: "handoff", body: "Nothing copied yet.", level: "warning" });
          return;
        }
        const r = await hc(["send", t.terminal, `${q(BIN)} paste`]);
        if (r.code !== 0) notify({ title: "handoff", body: r.stderr.trim() || "could not type into the terminal", level: "error" });
      } else if (c === "fork") {
        const s = await this.copy(t);
        if (s === "copied") this.split(t, "right", [BIN, "paste"]);
        else if (s === "pick") this.split(t, "right", [BIN, "fork", "--pick"]);
      }
    } finally {
      this.busy = false;
    }
  }

  // The popup's key: act, then close. The work keeps running after the
  // popup goes, since exec and hc start their programs at the call.
  key(e, cx) {
    cx.stop_propagation();
    const k = e.key;
    const action = k === "escape" ? null
      : k === "c" ? "copy"
      : k === "v" ? "paste"
      : k === "right" || k === "f" ? "fork"
      : undefined;
    if (action === undefined) return;
    this.dismiss();
    if (action) cx.spawn(async () => { await this.command(action); });
  }

  describe() {
    const c = this.clip;
    if (!c?.session_id) return "nothing copied yet";
    const where = `${c.name || "conversation"} in ${short(c.cwd)}`;
    return c.preview ? `${where} · “${c.preview}”` : where;
  }

  render() {
    const t = theme();
    const copied = Boolean(this.clip?.session_id);
    const root = v_flex().id("handoff").p(14).gap(8).bg(t.popover).text_color(t.foreground).text_size(12);
    if (this.popup) root.track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx));
    return root
      .child(h_flex().justify_between().items_center()
        .child(div().font_semibold().child("Handoff"))
        .child(div().text_color(t.muted).child("Esc cancel")))
      .child(h_flex().gap(6).items_center().text_color(copied ? t.foreground : t.muted)
        .child(div().text_color(t.dim).child("clipboard"))
        .child(div().flex_1().truncate().child(this.describe())))
      .children(ACTIONS.map(([key, , label]) =>
        h_flex().h(18).items_center().gap(12)
          .child(div().w(28).text_color(t.accent).child(key))
          .child(div().flex_1().child(label))));
  }
}
