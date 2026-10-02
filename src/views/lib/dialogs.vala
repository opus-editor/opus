/** What the user chose when asked about a tab (or file) with unsaved changes — Dialogs.confirm_discard()'s own return type. */
public enum DiscardChoice {
  SAVE,
  DISCARD,
  CANCEL,
}

/** Dialogs.add_response()'s own callback — fires once `response_id`'s button is clicked, right before the dialog closes. */
public delegate void ResponseActivated (string response_id);

/**
 * Lays out a response row exactly like AdwAlertDialog's own private
 * response-area gizmo (`allocate_responses`/`measure_responses_do` in
 * libadwaita 1.7's adw-alert-dialog.c, ported here since it isn't public
 * API): side by side, homogeneous width, while they fit; stacked full-width
 * otherwise, with the *last* child on top — children are iterated in
 * their normal (first-added-first) order either way, the bottom-up
 * allocation in the stacked branch is what puts the last one on top, not
 * a reordering step. Not Adw.Breakpoint: adding one to this dialog would
 * zero out its own minimum size (libadwaita's adaptive-layouts guide),
 * which is the opposite of what a response row that must never be
 * allocated shorter than its own content needs.
 */
private class ResponseAreaLayout : Gtk.LayoutManager {
  // AdwAlertDialog's own BUTTON_SPACING — not read from this app's CSS
  // (unlike Gtk.Box's spacing/border-spacing interplay elsewhere in
  // dialogs.vala), since AdwAlertDialog's own gizmo doesn't read it from
  // CSS either; it's this same hardcoded constant on both sides.
  private const int SPACING = 12;

  public override Gtk.SizeRequestMode get_request_mode (Gtk.Widget widget) {
    return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
  }

  public override void measure (Gtk.Widget widget, Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
    minimum_baseline = -1;
    natural_baseline = -1;

    if (orientation == Gtk.Orientation.HORIZONTAL) {
      int unused_nat, unused_min;
      measure_responses (widget, true, orientation, out minimum, out unused_nat);
      measure_responses (widget, false, orientation, out unused_min, out natural);
      return;
    }

    int wide_min, wide_nat = 0;
    if (for_size >= 0) {
      measure_responses (widget, false, Gtk.Orientation.HORIZONTAL, out wide_min, out wide_nat);
    }
    bool stacked = for_size >= 0 && wide_nat > for_size;
    measure_responses (widget, stacked, orientation, out minimum, out natural);
  }

  /**
   * `stacked` false measures a single side-by-side row: minimum is the
   * widest single response (the narrowest this could still be, one per
   * row), natural is every response at its own widest natural width,
   * laid end to end. `stacked` true measures a vertical stack instead:
   * every response's own height, summed. Same shape for both
   * orientations — `orientation` just decides which of a response's own
   * measurements (and which of these two meanings) is being asked for.
   */
  private static void measure_responses (Gtk.Widget widget, bool stacked, Gtk.Orientation orientation, out int minimum, out int natural) {
    bool horizontal = orientation == Gtk.Orientation.HORIZONTAL;
    int min = 0, nat = 0, response_min = 0, response_nat = 0, n_responses = 0;

    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
      int child_min, child_nat;
      child.measure (orientation, -1, out child_min, out child_nat, null, null);

      if (horizontal == stacked) {
        min = int.max (min, child_min);
        nat = int.max (nat, child_nat);
      } else if (horizontal) {
        response_min = int.max (response_min, child_min);
        response_nat = int.max (response_nat, child_nat);
        n_responses++;
      } else {
        min += child_min;
        nat += child_nat;
      }

      if (horizontal != stacked && child.get_next_sibling () != null) {
        min += SPACING;
        nat += SPACING;
      }
    }

    if (horizontal && !stacked) {
      min += response_min * n_responses;
      nat += response_nat * n_responses;
    }

    minimum = min;
    natural = nat;
  }

  public override void allocate (Gtk.Widget widget, int width, int height, int baseline) {
    int wide_min, wide_nat;
    measure_responses (widget, false, Gtk.Orientation.HORIZONTAL, out wide_min, out wide_nat);
    bool stacked = wide_nat > width;

    if (stacked) {
      int pos = height;
      for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        int child_height;
        child.measure (Gtk.Orientation.VERTICAL, -1, out child_height, null, null, null);
        pos -= child_height;
        child.allocate (width, child_height, -1, new Gsk.Transform ().translate (Graphene.Point () { x = 0, y = pos }));
        pos -= SPACING;
      }
      return;
    }

    int pos = 0;
    int remaining_width = width - SPACING * (int.max (0, count_children (widget) - 1));
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
      int n_remaining = count_children_from (child);
      int child_width = int.min ((remaining_width + n_remaining - 1) / n_remaining, remaining_width);
      remaining_width -= child_width;
      child.allocate (child_width, height, -1, new Gsk.Transform ().translate (Graphene.Point () { x = pos, y = 0 }));
      pos += child_width + SPACING;
    }
  }

  private static int count_children (Gtk.Widget widget) {
    return count_children_from (widget.get_first_child ());
  }

  private static int count_children_from (Gtk.Widget? first) {
    int count = 0;
    for (var child = first; child != null; child = child.get_next_sibling ()) {
      count++;
    }
    return count;
  }
}

/**
 * Shared builder for the modal dialogs used across TabBar, ExplorerPane,
 * TabFindResults, and MainWindow — same pattern as ContextMenu: a static
 * method per dialog shape, instantiating and discarding a dialog per call
 * rather than each call site hand-rolling its own responses.
 *
 * Built on a plain Adw.Dialog with hand-assembled content, not
 * Adw.AlertDialog: AlertDialog never calls adw_dialog_set_child()
 * internally, so its own `content_width` cap (372sp, 600sp at most with
 * `prefer_wide_layout`) can't be overridden — there's no public way to
 * make one wider. Building the content ourselves lets MIN_WIDTH apply
 * for real. The "message-area"/"response-area"/"alert" CSS classes below
 * are copied from AdwAlertDialog's own template/stylesheet (libadwaita
 * 1.7) so this reads identically to a native alert dialog, just wider —
 * they're undocumented internals, not public API, so a libadwaita
 * upgrade could change their styling or drop them. Their own
 * border-spacing/padding rules are left untouched (no custom CSS file
 * here) and each Gtk.Box below uses spacing 0 — GtkBoxLayout adds the
 * CSS border-spacing to the Box's own `spacing` property rather than
 * one overriding the other, so setting both doubles the gap.
 *
 * Not a Gtk.Widget subclass itself (nothing to instantiate and keep
 * around — every method builds, shows, and discards its own Adw.Dialog),
 * so this belongs in views/lib/ rather than views/components/, same
 * reasoning as SystemColor.
 */
public class Dialogs : Object {
  // Past Adw.AlertDialog's own natural-width cap (372sp) for a
  // heading/body pair, which otherwise reads as uncomfortably narrow.
  // This is content_width, a *preferred* size, not an enforced minimum
  // — a narrow window can still give the floating sheet less room than
  // this. See ResponseAreaLayout for how responses handle it (stacking,
  // same as AdwAlertDialog's own fallback) and Gtk.Button.can_shrink
  // below for the narrower-still case of one response's own label not
  // fitting even at full width.
  private const int MIN_WIDTH = 460;

  private Dialogs () {}

  /** The "unsaved changes" dialog shown before closing a tab — Save, Don't Save, or Cancel. `parent` is the widget to present it on. */
  public static async DiscardChoice confirm_discard (Gtk.Widget parent, string filename) {
    Gtk.Box response_area;
    var dialog = build (
      _("Save changes to “%s”?").printf (filename),
      _("Your changes will be lost if you don't save them."),
      out response_area
    );

    string response = "cancel";
    add_response (response_area, dialog, _("Don't Save"), null, "discard", (id) => response = id);
    add_response (response_area, dialog, _("Cancel"), null, "cancel", (id) => response = id);
    var save_button = add_response (response_area, dialog, _("Save"), "suggested-action", "save", (id) => response = id);
    dialog.default_widget = save_button;
    dialog.focus_widget = save_button;

    yield present_and_wait (dialog, parent);
    switch (response) {
      case "save":
        return DiscardChoice.SAVE;
      case "discard":
        return DiscardChoice.DISCARD;
      default:
        return DiscardChoice.CANCEL;
    }
  }

  /** A Cancel/`confirm_label` dialog for a destructive action (the `confirm` response styled red), defaulting to Cancel. `parent` is the widget to present it on. */
  public static async bool confirm_destructive (Gtk.Widget parent, string heading, string body, string confirm_label) {
    return yield confirm_with_style (parent, heading, body, confirm_label, "destructive-action", "cancel");
  }

  /** A Cancel/`confirm_label` dialog for a plain, non-destructive action (neither response styled, defaulting to `confirm`). `parent` is the widget to present it on. */
  public static async bool confirm (Gtk.Widget parent, string heading, string body, string confirm_label) {
    return yield confirm_with_style (parent, heading, body, confirm_label, null, "confirm");
  }

  private static async bool confirm_with_style (Gtk.Widget parent, string heading, string body, string confirm_label, string? confirm_style_class, string default_response) {
    Gtk.Box response_area;
    var dialog = build (heading, body, out response_area);

    string response = "cancel";
    var cancel_button = add_response (response_area, dialog, _("Cancel"), null, "cancel", (id) => response = id);
    var confirm_button = add_response (response_area, dialog, confirm_label, confirm_style_class, "confirm", (id) => response = id);
    var default_button = default_response == "confirm" ? confirm_button : cancel_button;
    dialog.default_widget = default_button;
    dialog.focus_widget = default_button;

    yield present_and_wait (dialog, parent);
    return response == "confirm";
  }

  /** A plain OK-only error dialog. `parent` is the widget to present it on. */
  public static void show_error (Gtk.Widget parent, string message) {
    Gtk.Box response_area;
    var dialog = build (_("Error"), message, out response_area);
    var ok_button = add_response (response_area, dialog, _("OK"), null, "ok", (id) => {});
    dialog.default_widget = ok_button;
    dialog.focus_widget = ok_button;
    dialog.present (parent);
  }

  /** The heading/body message area and an empty button row, styled to match AdwAlertDialog, `MIN_WIDTH` wide. Callers add their own responses to `response_area`. */
  private static Adw.Dialog build (string heading, string body, out Gtk.Box response_area) {
    // halign stays at its FILL default, not CENTER: a centered halign
    // shrinks the label to its own natural width before deciding where
    // to wrap, breaking lines earlier than the dialog's real width
    // requires. xalign centers the text itself once laid out over the
    // full available width — same as AdwAlertDialog's own heading_label/
    // body_label template (xalign="0.5", no halign set at all).
    var heading_label = new Gtk.Label (heading) {
      wrap = true,
      wrap_mode = Pango.WrapMode.WORD_CHAR,
      justify = Gtk.Justification.CENTER,
      xalign = 0.5f,
    };
    heading_label.add_css_class ("heading-bin");
    heading_label.add_css_class ("title-2");

    var body_label = new Gtk.Label (body) {
      wrap = true,
      wrap_mode = Pango.WrapMode.WORD_CHAR,
      justify = Gtk.Justification.CENTER,
      xalign = 0.5f,
      vexpand = true,
    };
    body_label.add_css_class ("body");

    // Spacing 0: message-area's own CSS rule already sets border-spacing
    // (10px for this has-heading+has-body combination) — GtkBoxLayout
    // adds that to whatever's passed here instead of one replacing the
    // other, so a non-zero value here doubles the real gap.
    var message_area = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
    message_area.add_css_class ("message-area");
    message_area.add_css_class ("has-heading");
    message_area.add_css_class ("has-body");
    message_area.append (heading_label);
    message_area.append (body_label);

    // ResponseAreaLayout does its own measure/allocate (see its own doc
    // comment) — Box's own spacing/homogeneous/orientation are unused.
    response_area = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
    response_area.set_layout_manager (new ResponseAreaLayout ());
    response_area.add_css_class ("response-area");

    var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
    content.append (message_area);
    content.append (response_area);

    var dialog = new Adw.Dialog () {
      content_width = MIN_WIDTH,
      child = content,
      // AdwAlertDialog's own template pins this to FLOATING too —
      // AUTO (the Adw.Dialog default) drops to a BOTTOM_SHEET once the
      // window gets narrower than our content, which not only looks
      // wrong for an alert but also fights MIN_WIDTH by letting the
      // sheet get clamped below it.
      presentation_mode = Adw.DialogPresentationMode.FLOATING,
    };
    dialog.add_css_class ("alert");
    dialog.add_css_class ("opus-dialog");

    return dialog;
  }

  /** Appends a response button styled `style_class` (`"suggested-action"`/`"destructive-action"`/`null`) to `response_area`, calling `on_activated` with `response_id` and closing `dialog` when clicked. */
  private static Gtk.Button add_response (Gtk.Box response_area, Adw.Dialog dialog, string label, string? style_class, string response_id, owned ResponseActivated on_activated) {
    var button = new Gtk.Button.with_label (label) {
      // AdwAlertDialog's own responses do this too: past MIN_WIDTH, this
      // is how a 3-response row (or any response_label that's just too
      // long) handles a narrower window — the label ellipsizes instead
      // of forcing the row, and the dialog along with it, wider than
      // its parent.
      can_shrink = true,
    };
    if (style_class != null) {
      button.add_css_class (style_class);
    }
    button.clicked.connect (() => {
      on_activated (response_id);
      dialog.close ();
    });
    response_area.append (button);
    return button;
  }

  /** Shows `dialog` on `parent` and suspends the caller until it closes (a button response, Escape, or the window closing). */
  private static async void present_and_wait (Adw.Dialog dialog, Gtk.Widget parent) {
    dialog.closed.connect (() => present_and_wait.callback ());
    dialog.present (parent);
    yield;
  }
}
