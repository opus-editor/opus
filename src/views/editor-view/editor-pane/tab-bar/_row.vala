/**
 * The row the {@link TabBarPill}s sit in, laying them out itself: a plain
 * Gtk.Box can only reorder its children, so a tab changing place would
 * jump straight to its new slot. Here every pill has an `x` of its own
 * that slides to where the order puts it — libadwaita's AdwTabBox does
 * the same, with the same 250ms. Between two pills that are neither
 * selected, pressed nor being dragged, a thin separator sits in the
 * gap, as AdwTabBox draws one; the pills themselves stay the row's
 * last children, so a caller walking the children from the end still
 * finds a pill.
 */
namespace EditorView.EditorPane {
  public class TabBarRow : Gtk.Widget {
    private const int SPACING = 4;
    private const uint SLIDE_DURATION_MS = 250;

    private class Slot : Object {
      /** Where the pill is drawn right now. */
      public double x = 0;
      /** Where the order puts it. */
      public double target_x = 0;
      /** A pill's first layout puts it straight at its slot — nothing to slide from. */
      public bool placed = false;
      public Adw.TimedAnimation? slide = null;
      /** The one in the gap to the left of the pill, hidden for the first pill and around a lifted one. */
      public Gtk.Separator separator = new Gtk.Separator (Gtk.Orientation.VERTICAL) { can_target = false };
      public ulong state_handler = 0;
      public ulong classes_handler = 0;
    }

    private HashTable<Gtk.Widget, Slot> slots = new HashTable<Gtk.Widget, Slot> (direct_hash, direct_equal);

    construct {
      add_css_class ("tab-row");
    }

    public void append (Gtk.Widget child) {
      var slot = new Slot ();
      slots[child] = slot;
      // Separators go first, pills last — see the class comment.
      slot.separator.insert_after (this, null);
      child.insert_before (this, null);
      // Press is a state flag; selected and dragging are the pill's own
      // CSS classes, which only announce themselves this way.
      slot.state_handler = child.state_flags_changed.connect (() => update_separators ());
      slot.classes_handler = child.notify["css-classes"].connect (() => update_separators ());
      update_separators ();
    }

    public void remove (Gtk.Widget child) {
      var slot = slots[child];
      if (slot != null) {
        slot.slide?.pause ();
        child.disconnect (slot.state_handler);
        child.disconnect (slot.classes_handler);
        slot.separator.unparent ();
        slots.remove (child);
      }
      child.unparent ();
      update_separators ();
    }

    /** `child` goes right after `sibling` (first, for null); the others slide out of its way. */
    public void reorder_child_after (Gtk.Widget child, Gtk.Widget? sibling) {
      child.insert_after (this, sibling);
      update_separators ();
      queue_allocate ();
    }

    /** AdwTabBox's own rule, minus hover: no separator before the first pill, nor on either side of one that is selected, pressed or being dragged. */
    private void update_separators () {
      Gtk.Widget? previous = null;
      for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
        var slot = slots[child];
        if (slot == null) {
          continue;
        }
        var hidden = previous == null || lifts_separator (previous) || lifts_separator (child);
        if (hidden) {
          slot.separator.add_css_class ("hidden");
        } else {
          slot.separator.remove_css_class ("hidden");
        }
        previous = child;
      }
    }

    private static bool lifts_separator (Gtk.Widget pill) {
      if (pill.has_css_class ("active") || pill.has_css_class ("dragging")) {
        return true;
      }
      return (pill.get_state_flags () & Gtk.StateFlags.ACTIVE) != 0;
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
      minimum = 0;
      natural = 0;
      minimum_baseline = -1;
      natural_baseline = -1;
      var count = 0;
      for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
        if (!slots.contains (child) || !child.should_layout ()) {
          continue;
        }
        int child_minimum, child_natural;
        child.measure (orientation, -1, out child_minimum, out child_natural, null, null);
        if (orientation == Gtk.Orientation.HORIZONTAL) {
          minimum += child_minimum;
          natural += child_natural;
          count++;
        } else {
          minimum = int.max (minimum, child_minimum);
          natural = int.max (natural, child_natural);
        }
      }
      if (orientation == Gtk.Orientation.HORIZONTAL && count > 1) {
        minimum += SPACING * (count - 1);
        natural += SPACING * (count - 1);
      }
    }

    public override void size_allocate (int width, int height, int baseline) {
      double x = 0;
      for (var child = get_first_child (); child != null; child = child.get_next_sibling ()) {
        var slot = slots[child];
        if (slot == null || !child.should_layout ()) {
          continue;
        }
        int child_minimum, child_natural;
        child.measure (Gtk.Orientation.HORIZONTAL, -1, out child_minimum, out child_natural, null, null);
        slot.target_x = x;
        x += child_natural + SPACING;
        settle (slot);
        child.allocate (child_natural, height, -1, new Gsk.Transform ().translate (Graphene.Point () { x = (float) slot.x, y = 0 }));
        allocate_separator (slot, height);
      }
    }

    /** Centered in the gap to the left of the pill, moving with it; full height, its CSS margins keeping it off the edges. */
    private void allocate_separator (Slot slot, int height) {
      int separator_width, natural_width, minimum_height, natural_height;
      slot.separator.measure (Gtk.Orientation.HORIZONTAL, -1, out separator_width, out natural_width, null, null);
      slot.separator.measure (Gtk.Orientation.VERTICAL, -1, out minimum_height, out natural_height, null, null);
      // On a whole pixel, or a 1px line smears over two half-tinted columns.
      var separator_x = Math.round (slot.x - (SPACING + separator_width) / 2.0);
      slot.separator.allocate (separator_width, height, -1, new Gsk.Transform ().translate (Graphene.Point () { x = (float) separator_x, y = 0 }));
    }

    /** Puts `slot` where its order says: straight there on its first layout, sliding otherwise — and never restarting a slide already headed there. */
    private void settle (Slot slot) {
      if (!slot.placed) {
        slot.x = slot.target_x;
        slot.placed = true;
        return;
      }
      if (slot.x == slot.target_x) {
        return;
      }
      if (slot.slide != null && slot.slide.state == Adw.AnimationState.PLAYING && slot.slide.value_to == slot.target_x) {
        return;
      }
      slot.slide?.pause ();
      var target = new Adw.CallbackAnimationTarget ((value) => {
        slot.x = value;
        queue_allocate ();
      });
      slot.slide = new Adw.TimedAnimation (this, slot.x, slot.target_x, SLIDE_DURATION_MS, target);
      slot.slide.play ();
    }

    public override void dispose () {
      foreach (var slot in slots.get_values ()) {
        slot.slide?.pause ();
      }
      slots.remove_all ();
      Gtk.Widget? child;
      while ((child = get_first_child ()) != null) {
        child.unparent ();
      }
      base.dispose ();
    }
  }
}
